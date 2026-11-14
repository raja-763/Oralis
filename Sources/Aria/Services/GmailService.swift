import Foundation

/// Gmail REST API (v1) implementation.
/// Auth token is retrieved from Keychain using account.keychainToken.
final class GmailService: EmailService {
    let account: EmailAccount
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    init(account: EmailAccount) {
        self.account = account
    }

    // MARK: - Auth + HTTP

    // Keychain reads are slow (about a second each), so the access token is kept in
    // memory after the first read instead of being fetched again for every request.
    private static let tokenLock = NSLock()
    private static var cachedTokens: [UUID: String] = [:]

    private static func cachedToken(for id: UUID) -> String? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return cachedTokens[id]
    }

    private static func cacheToken(_ token: String, for id: UUID) {
        tokenLock.lock(); defer { tokenLock.unlock() }
        cachedTokens[id] = token
    }

    // The app identifies threads by its own UUIDs; Gmail needs its own thread IDs.
    private static var remoteIDs: [UUID: String] = [:]

    private static func remember(_ thread: EmailThread) {
        tokenLock.lock(); defer { tokenLock.unlock() }
        remoteIDs[thread.id] = thread.remoteThreadID
    }

    /// Makes threads restored from the on-disk cache usable for actions right away.
    static func register(_ threads: [EmailThread]) { threads.forEach(remember) }

    private func gmailID(for id: UUID) throws -> String {
        GmailService.tokenLock.lock(); defer { GmailService.tokenLock.unlock() }
        guard let remote = GmailService.remoteIDs[id] else {
            throw OralisError.apiError("That email is no longer loaded. Ask for your emails again and retry.")
        }
        return remote
    }

    /// Applies one change to each thread and fails if any thread could not be changed.
    private func modifyEach(_ ids: [UUID], path: String, body: Data? = nil) async throws {
        var failures = 0
        for id in ids {
            do {
                _ = try await execute("threads/\(try gmailID(for: id))/\(path)", method: "POST", body: body)
            } catch { failures += 1 }
        }
        if failures > 0 {
            throw OralisError.apiError("\(failures) of \(ids.count) emails could not be changed.")
        }
    }

    private func authToken() throws -> String {
        if let cached = GmailService.cachedToken(for: account.id) { return cached }
        guard let token = KeychainService.loadAccessToken(for: account.id),
              !token.isEmpty
        else { throw OralisError.notAuthenticated }
        GmailService.cacheToken(token, for: account.id)
        return token
    }

    private func makeRequest(_ path: String, method: String = "GET",
                              body: Data? = nil, token: String) throws -> URLRequest {
        // Use string concat, not appendingPathComponent — the latter percent-encodes
        // '?' and '&', breaking every URL that has query parameters.
        guard let url = URL(string: baseURL.absoluteString + "/" + path) else {
            throw OralisError.apiError("Oralis built an invalid Gmail request.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    /// Executes a Gmail API call, refreshing the token once on 401.
    /// Runs a Gmail call; when Google answers that the per-minute quota is used up,
    /// waits and tries again instead of failing.
    private func execute(_ path: String, method: String = "GET",
                          body: Data? = nil) async throws -> Data {
        var delay: UInt64 = 4
        for _ in 0..<4 {
            do {
                return try await executeOnce(path, method: method, body: body)
            } catch OralisError.apiError(let message)
                where message.contains("Quota exceeded") || message.contains("rateLimitExceeded") {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay *= 2
            }
        }
        return try await executeOnce(path, method: method, body: body)
    }

    private func executeOnce(_ path: String, method: String = "GET",
                              body: Data? = nil) async throws -> Data {
        var token = try authToken()
        let (data, response) = try await URLSession.shared.data(for: try makeRequest(path, method: method, body: body, token: token))
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            token = try await OAuthService.refreshGoogleAccessToken(for: account.id)
            GmailService.cacheToken(token, for: account.id)
            let (data2, response2) = try await URLSession.shared.data(for: try makeRequest(path, method: method, body: body, token: token))
            if let http2 = response2 as? HTTPURLResponse, !(200...299).contains(http2.statusCode) {
                let msg = String(data: data2, encoding: .utf8) ?? "HTTP \(http2.statusCode)"
                throw OralisError.apiError(msg)
            }
            return data2
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OralisError.apiError(msg)
        }
        return data
    }

    // MARK: - EmailService

    func fetchThreads(limit: Int) async throws -> [EmailThread] {
        let data = try await execute("threads?maxResults=\(limit)&labelIds=INBOX")
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        // Fetch in parallel, four at a time, keeping Gmail's newest-first order.
        let ids = (list.threads ?? []).map(\.id)
        var results = [EmailThread?](repeating: nil, count: ids.count)
        var next = 0
        await withTaskGroup(of: (Int, EmailThread?).self) { group in
            func addNext() {
                guard next < ids.count else { return }
                let index = next
                next += 1
                group.addTask { (index, try? await self.fetchThread(id: ids[index])) }
            }
            for _ in 0..<4 { addNext() }
            for await (index, thread) in group {
                results[index] = thread
                addNext()
            }
        }
        return results.compactMap { $0 }
    }

    private func fetchThread(id: String) async throws -> EmailThread {
        let data = try await execute("threads/\(id)?format=full")
        let raw = try JSONDecoder().decode(GmailThread.self, from: data)
        var thread = raw.toEmailThread(accountID: account.id)
        // Invites sent as an attached .ics file are fetched so they can be added to the calendar.
        for i in thread.messages.indices {
            guard thread.messages[i].calendarInvite == nil, let attachment = thread.messages[i].calendarAttachmentID,
                  let data = try? await execute("messages/\(thread.messages[i].remoteID)/attachments/\(attachment)"),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let encoded = object["data"] as? String
            else { continue }
            thread.messages[i].calendarInvite = ICSParser.parse(GmailService.decodeBase64URL(encoded))
        }
        GmailService.remember(thread)
        return thread
    }

    static func decodeBase64URL(_ s: String) -> String {
        var fixed = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while fixed.count % 4 != 0 { fixed += "=" }
        guard let data = Data(base64Encoded: fixed, options: .ignoreUnknownCharacters) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func fetchMessage(id: String) async throws -> EmailMessage {
        let data = try await execute("messages/\(id)?format=full")
        let raw = try JSONDecoder().decode(GmailMessage.self, from: data)
        return raw.toEmailMessage(accountID: account.id)
    }

    func sendMessage(_ draft: DraftMessage) async throws {
        let raw = draft.toMIME()
        let encoded = Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let body = try JSONEncoder().encode(["raw": encoded])
        _ = try await execute("messages/send", method: "POST", body: body)
    }

    func deleteThreads(ids: [UUID]) async throws {
        // Moves to Trash (recoverable for 30 days) rather than deleting permanently, and checks
        // Gmail's answer: an email only counts as deleted if Gmail says it is now in the Trash.
        var failed = 0
        for id in ids {
            do {
                let data = try await execute("threads/\(try gmailID(for: id))/trash", method: "POST")
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let messages = object?["messages"] as? [[String: Any]] ?? []
                let inTrash = messages.contains { ($0["labelIds"] as? [String])?.contains("TRASH") == true }
                if !inTrash { failed += 1; oralisLog("delete: Gmail did not report the thread in the trash") }
            } catch {
                failed += 1
                oralisLog("delete: request failed: \(String(describing: error).prefix(160))")
            }
        }
        if failed > 0 {
            throw OralisError.apiError("\(failed) of \(ids.count) emails could not be moved to the trash.")
        }
    }

    func archiveThreads(ids: [UUID]) async throws {
        let body = try JSONEncoder().encode(GmailModify(addLabelIds: [], removeLabelIds: ["INBOX"]))
        try await modifyEach(ids, path: "modify", body: body)
    }

    func markRead(ids: [UUID], read: Bool) async throws {
        let mod = read
            ? GmailModify(addLabelIds: [], removeLabelIds: ["UNREAD"])
            : GmailModify(addLabelIds: ["UNREAD"], removeLabelIds: [])
        let body = try JSONEncoder().encode(mod)
        try await modifyEach(ids, path: "modify", body: body)
    }

    func starThreads(ids: [UUID], starred: Bool) async throws {
        let mod = starred
            ? GmailModify(addLabelIds: ["STARRED"], removeLabelIds: [])
            : GmailModify(addLabelIds: [], removeLabelIds: ["STARRED"])
        let body = try JSONEncoder().encode(mod)
        try await modifyEach(ids, path: "modify", body: body)
    }

    func searchThreads(query: String) async throws -> [EmailThread] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Gmail leaves Spam and Trash out of searches unless asked to include them.
        let lower = query.lowercased()
        let everywhere = lower.contains("in:spam") || lower.contains("in:trash") || lower.contains("in:anywhere")
        let data = try await execute("threads?q=\(encoded)&maxResults=15\(everywhere ? "&includeSpamTrash=true" : "")")
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        // Fetch in parallel, four at a time, keeping Gmail's newest-first order.
        let ids = (list.threads ?? []).map(\.id)
        var results = [EmailThread?](repeating: nil, count: ids.count)
        var next = 0
        await withTaskGroup(of: (Int, EmailThread?).self) { group in
            func addNext() {
                guard next < ids.count else { return }
                let index = next
                next += 1
                group.addTask { (index, try? await self.fetchThread(id: ids[index])) }
            }
            for _ in 0..<4 { addNext() }
            for await (index, thread) in group {
                results[index] = thread
                addNext()
            }
        }
        return results.compactMap { $0 }
    }

    func fetchSpam(limit: Int) async throws -> [EmailThread] {
        let data = try await execute("threads?maxResults=\(limit)&labelIds=SPAM")
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        // Fetch in parallel, four at a time, keeping Gmail's newest-first order.
        let ids = (list.threads ?? []).map(\.id)
        var results = [EmailThread?](repeating: nil, count: ids.count)
        var next = 0
        await withTaskGroup(of: (Int, EmailThread?).self) { group in
            func addNext() {
                guard next < ids.count else { return }
                let index = next
                next += 1
                group.addTask { (index, try? await self.fetchThread(id: ids[index])) }
            }
            for _ in 0..<4 { addNext() }
            for await (index, thread) in group {
                results[index] = thread
                addNext()
            }
        }
        return results.compactMap { $0 }
    }

    func unsubscribe(from message: EmailMessage) async throws -> UnsubscribeResult {
        try await UnsubscribeService.shared.unsubscribe(from: message, via: account)
    }

    /// Restores threads from Spam, Trash or the archive to the inbox.
    func moveToInbox(ids: [UUID]) async throws {
        // Untrash first; it is harmless for threads that are not in Trash.
        for id in ids {
            _ = try? await execute("threads/\(try gmailID(for: id))/untrash", method: "POST")
        }
        let mod = GmailModify(addLabelIds: ["INBOX"], removeLabelIds: ["SPAM"])
        try await modifyEach(ids, path: "modify", body: try JSONEncoder().encode(mod))
    }

    func moveToSpam(ids: [UUID]) async throws {
        let mod = GmailModify(addLabelIds: ["SPAM"], removeLabelIds: ["INBOX"])
        let body = try JSONEncoder().encode(mod)
        try await modifyEach(ids, path: "modify", body: body)
    }
}

// MARK: - Gmail API response shapes

private struct GmailThreadList: Decodable {
    struct Item: Decodable { var id: String }
    var threads: [Item]?
}

private struct GmailModify: Encodable {
    var addLabelIds: [String]
    var removeLabelIds: [String]
}

private struct GmailThread: Decodable {
    var id: String
    var messages: [GmailMessage]?

    func toEmailThread(accountID: UUID) -> EmailThread {
        let msgs = messages?.compactMap { $0.toEmailMessage(accountID: accountID) } ?? []
        let latest = msgs.last ?? EmailMessage.placeholder(accountID: accountID)
        return EmailThread(
            id: UUID(),
            remoteThreadID: id,
            accountID: accountID,
            subject: latest.subject,
            participants: msgs.map(\.from),
            messages: msgs,
            latestDate: latest.date,
            isRead: msgs.allSatisfy(\.isRead),
            isStarred: latest.isStarred,
            labels: latest.labels,
            snippet: latest.bodyPlain.prefix(120).description
        )
    }
}

private struct GmailMessage: Decodable {
    var id: String
    var payload: Payload?
    var labelIds: [String]?
    var internalDate: String?

    struct Payload: Decodable {
        var mimeType: String?
        var filename: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Payload]?
    }
    struct Header: Decodable { var name: String; var value: String }
    struct Body: Decodable { var data: String?; var attachmentId: String? }

    func toEmailMessage(accountID: UUID) -> EmailMessage {
        let headers = payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value ?? ""
        }
        let from = EmailAddress(name: "", address: header("from"))
        let subject = header("subject")
        let dateStr = header("date")
        let date = Date(gmailInternalDate: internalDate ?? "0")
        let isRead = !(labelIds?.contains("UNREAD") ?? false)
        let isStarred = labelIds?.contains("STARRED") ?? false
        let labels = labelIds ?? []
        let bodyHTML = extractHTML(payload)
        var bodyText = extractPlainText(payload)
        if bodyText.isEmpty, !bodyHTML.isEmpty { bodyText = GmailMessage.stripHTML(bodyHTML) }
        // Links come from the HTML (where unsubscribe links live), plus any bare URLs in the text.
        var links = HTMLLinkExtractor.extract(from: bodyHTML)
        let seen = Set(links.map(\.url))
        links += HTMLLinkExtractor.extract(from: bodyText).filter { !seen.contains($0.url) }
        let calendarPart = findPart(payload) { ($0.mimeType ?? "").lowercased() == "text/calendar" || ($0.filename ?? "").lowercased().hasSuffix(".ics") }
        let invite = calendarPart?.body?.data.flatMap { ICSParser.parse(decodeBase64($0)) }
        let (unsubURL, unsubEmail, unsubSubject) = parseUnsubscribe(header("list-unsubscribe"))
        let oneClick = header("list-unsubscribe-post").lowercased().contains("one-click")

        return EmailMessage(
            id: UUID(), remoteID: id, accountID: accountID,
            from: from, to: [], cc: [],
            subject: subject, bodyPlain: bodyText, bodyHTML: bodyHTML,
            date: date, isRead: isRead, isStarred: isStarred,
            labels: labels, links: links,
            unsubscribeURL: unsubURL, unsubscribeEmail: unsubEmail,
            unsubscribeEmailSubject: unsubSubject, unsubscribeOneClick: oneClick,
            calendarInvite: invite, calendarAttachmentID: calendarPart?.body?.attachmentId
        )
    }

    private func findPart(_ p: Payload?, where match: (Payload) -> Bool) -> Payload? {
        guard let p else { return nil }
        if match(p) { return p }
        for part in p.parts ?? [] { if let found = findPart(part, where: match) { return found } }
        return nil
    }

    private func extractPlainText(_ p: Payload?) -> String {
        if let part = findPart(p, where: { ($0.mimeType ?? "").lowercased() == "text/plain" && $0.body?.data != nil }) {
            return decodeBase64(part.body?.data)
        }
        // A single-part message with no explicit type.
        if let p, p.parts == nil, p.mimeType == nil, p.body?.data != nil { return decodeBase64(p.body?.data) }
        return ""
    }

    private func extractHTML(_ p: Payload?) -> String {
        guard let part = findPart(p, where: { ($0.mimeType ?? "").lowercased() == "text/html" && $0.body?.data != nil })
        else { return "" }
        return decodeBase64(part.body?.data)
    }

    /// Readable text from an HTML-only email.
    static func stripHTML(_ html: String) -> String {
        var s = html
        for pattern in ["<style[^>]*>.*?</style>", "<script[^>]*>.*?</script>", "<!--.*?-->"] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(br|/p|/div|/tr|/h[1-6]|/li)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "'"), ("&zwnj;", "")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = s.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
             .replacingOccurrences(of: "\n\\s*\n+", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeBase64(_ s: String?) -> String {
        guard let s else { return "" }
        var fixed = s.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        while fixed.count % 4 != 0 { fixed += "=" }
        guard let data = Data(base64Encoded: fixed, options: .ignoreUnknownCharacters),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    /// The header lists targets in angle brackets, e.g. <https://x/u?a=1,2>, <mailto:u@x.com?subject=unsubscribe>.
    /// It may be folded over several lines and URLs may contain commas.
    private func parseUnsubscribe(_ header: String) -> (URL?, String?, String?) {
        var url: URL?
        var email: String?
        var subject: String?
        var search = header[...]
        while let open = search.firstIndex(of: "<"), let close = search[open...].firstIndex(of: ">") {
            let target = search[search.index(after: open)..<close]
                .components(separatedBy: .whitespacesAndNewlines).joined()
            search = search[search.index(after: close)...]
            if target.lowercased().hasPrefix("mailto:") {
                let comps = URLComponents(string: target)
                let address = comps?.path ?? String(target.dropFirst(7)).components(separatedBy: "?").first ?? ""
                if address.contains("@") { email = address }
                subject = comps?.queryItems?.first { $0.name.lowercased() == "subject" }?.value
            } else if let u = URL(string: target), u.scheme == "https" || u.scheme == "http" {
                if url == nil { url = u }
            }
        }
        return (url, email, subject)
    }
}

private extension Date {
    init(gmailInternalDate string: String) {
        let ms = Double(string) ?? 0
        self = Date(timeIntervalSince1970: ms / 1000)
    }
}
