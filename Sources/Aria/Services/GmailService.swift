import Foundation

/// Gmail REST API (v1) implementation.
/// Auth token is retrieved from Keychain using account.keychainToken.
final class GmailService: EmailService {
    let account: EmailAccount
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    init(account: EmailAccount) {
        self.account = account
    }

    // MARK: - Auth

    private func authToken() throws -> String {
        guard let token = KeychainService.shared.load(key: account.keychainToken),
              !token.isEmpty
        else { throw OralisError.notAuthenticated }
        return token
    }

    private func request(_ path: String, method: String = "GET",
                          body: Data? = nil) throws -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try authToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    // MARK: - EmailService

    func fetchThreads(limit: Int) async throws -> [EmailThread] {
        let req = try request("threads?maxResults=\(limit)&labelIds=INBOX")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        var threads: [EmailThread] = []
        for item in list.threads ?? [] {
            if let thread = try? await fetchThread(id: item.id) {
                threads.append(thread)
            }
        }
        return threads
    }

    private func fetchThread(id: String) async throws -> EmailThread {
        let req = try request("threads/\(id)?format=full")
        let (data, _) = try await URLSession.shared.data(for: req)
        let raw = try JSONDecoder().decode(GmailThread.self, from: data)
        return raw.toEmailThread(accountID: account.id)
    }

    func fetchMessage(id: String) async throws -> EmailMessage {
        let req = try request("messages/\(id)?format=full")
        let (data, _) = try await URLSession.shared.data(for: req)
        let raw = try JSONDecoder().decode(GmailMessage.self, from: data)
        return raw.toEmailMessage(accountID: account.id)
    }

    func sendMessage(_ draft: DraftMessage) async throws {
        let raw = draft.toMIME()
        let encoded = Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let body = try JSONEncoder().encode(["raw": encoded])
        let req = try request("messages/send", method: "POST", body: body)
        _ = try await URLSession.shared.data(for: req)
    }

    func deleteThreads(ids: [UUID]) async throws {
        // Map UUID → remote ID via local store, then call threads/batchDelete
        let body = try JSONEncoder().encode(["ids": ids.map(\.uuidString)])
        let req = try request("threads/batchDelete", method: "POST", body: body)
        _ = try await URLSession.shared.data(for: req)
    }

    func archiveThreads(ids: [UUID]) async throws {
        let body = try JSONEncoder().encode(GmailModify(addLabelIds: [], removeLabelIds: ["INBOX"]))
        for id in ids {
            var req = try request("threads/\(id.uuidString)/modify", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func markRead(ids: [UUID], read: Bool) async throws {
        let mod = read
            ? GmailModify(addLabelIds: [], removeLabelIds: ["UNREAD"])
            : GmailModify(addLabelIds: ["UNREAD"], removeLabelIds: [])
        let body = try JSONEncoder().encode(mod)
        for id in ids {
            let req = try request("threads/\(id.uuidString)/modify", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func starThreads(ids: [UUID], starred: Bool) async throws {
        let mod = starred
            ? GmailModify(addLabelIds: ["STARRED"], removeLabelIds: [])
            : GmailModify(addLabelIds: [], removeLabelIds: ["STARRED"])
        let body = try JSONEncoder().encode(mod)
        for id in ids {
            let req = try request("threads/\(id.uuidString)/modify", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func searchThreads(query: String) async throws -> [EmailThread] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let req = try request("threads?q=\(encoded)&maxResults=50")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        var threads: [EmailThread] = []
        for item in list.threads ?? [] {
            if let thread = try? await fetchThread(id: item.id) {
                threads.append(thread)
            }
        }
        return threads
    }

    func fetchSpam(limit: Int) async throws -> [EmailThread] {
        let req = try request("threads?maxResults=\(limit)&labelIds=SPAM")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GmailThreadList.self, from: data)
        var threads: [EmailThread] = []
        for item in list.threads ?? [] {
            if let thread = try? await fetchThread(id: item.id) {
                threads.append(thread)
            }
        }
        return threads
    }

    func unsubscribe(from message: EmailMessage) async throws {
        try await UnsubscribeService.shared.unsubscribe(from: message, via: account)
    }

    func moveToSpam(ids: [UUID]) async throws {
        let mod = GmailModify(addLabelIds: ["SPAM"], removeLabelIds: ["INBOX"])
        let body = try JSONEncoder().encode(mod)
        for id in ids {
            let req = try request("threads/\(id.uuidString)/modify", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
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
        var headers: [Header]?
        var body: Body?
        var parts: [Payload]?
    }
    struct Header: Decodable { var name: String; var value: String }
    struct Body: Decodable { var data: String? }

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
        let bodyText = extractPlainText(payload)
        let bodyHTML = extractHTML(payload)
        let links = HTMLLinkExtractor.extract(from: bodyHTML.isEmpty ? bodyText : bodyHTML)
        let (unsubURL, unsubEmail) = parseUnsubscribe(header("list-unsubscribe"))

        return EmailMessage(
            id: UUID(), remoteID: id, accountID: accountID,
            from: from, to: [], cc: [],
            subject: subject, bodyPlain: bodyText, bodyHTML: bodyHTML,
            date: date, isRead: isRead, isStarred: isStarred,
            labels: labels, links: links,
            unsubscribeURL: unsubURL, unsubscribeEmail: unsubEmail,
            calendarInvite: nil
        )
    }

    private func extractPlainText(_ p: Payload?) -> String {
        guard let p else { return "" }
        if p.body?.data != nil, p.parts == nil {
            return decodeBase64(p.body?.data)
        }
        for part in p.parts ?? [] {
            let result = extractPlainText(part)
            if !result.isEmpty { return result }
        }
        return ""
    }

    private func extractHTML(_ p: Payload?) -> String { "" }

    private func decodeBase64(_ s: String?) -> String {
        guard let s else { return "" }
        let fixed = s.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: fixed, options: .ignoreUnknownCharacters),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    private func parseUnsubscribe(_ header: String) -> (URL?, String?) {
        // Header looks like: <https://...>, <mailto:...>
        var url: URL?
        var email: String?
        let parts = header.split(separator: ",")
        for part in parts {
            let clean = part.trimmingCharacters(in: .init(charactersIn: " <>"))
            if clean.hasPrefix("mailto:") {
                email = String(clean.dropFirst(7))
            } else if let u = URL(string: clean), u.scheme == "https" || u.scheme == "http" {
                url = u
            }
        }
        return (url, email)
    }
}

private extension Date {
    init(gmailInternalDate string: String) {
        let ms = Double(string) ?? 0
        self = Date(timeIntervalSince1970: ms / 1000)
    }
}
