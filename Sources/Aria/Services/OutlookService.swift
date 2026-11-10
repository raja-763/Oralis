import Foundation

/// Microsoft Graph API (Outlook / Exchange / Office 365).
final class OutlookService: EmailService {
    let account: EmailAccount
    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0/me")!

    init(account: EmailAccount) { self.account = account }

    private func token() throws -> String {
        guard let t = KeychainService.shared.load(key: account.keychainToken) else {
            throw OralisError.notAuthenticated
        }
        return t
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    func fetchThreads(limit: Int) async throws -> [EmailThread] {
        let req = try request("mailFolders/inbox/messages?$top=\(limit)&$orderby=receivedDateTime desc")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GraphMessageList.self, from: data)
        return list.value.map { $0.toEmailThread(accountID: account.id) }
    }

    func fetchMessage(id: String) async throws -> EmailMessage {
        let req = try request("messages/\(id)")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(GraphMessage.self, from: data).toEmailMessage(accountID: account.id)
    }

    func sendMessage(_ draft: DraftMessage) async throws {
        struct SendBody: Encodable {
            struct Msg: Encodable {
                struct Recipient: Encodable { struct Addr: Encodable { var address: String }; var emailAddress: Addr }
                var subject: String
                var body: MsgBody
                var toRecipients: [Recipient]
            }
            struct MsgBody: Encodable { var contentType: String; var content: String }
            var message: Msg
            var saveToSentItems: Bool = true
        }
        let msg = SendBody.Msg(
            subject: draft.subject,
            body: .init(contentType: "Text", content: draft.body),
            toRecipients: draft.to.map { .init(emailAddress: .init(address: $0.address)) }
        )
        let body = try JSONEncoder().encode(SendBody(message: msg))
        let req = try request("sendMail", method: "POST", body: body)
        _ = try await URLSession.shared.data(for: req)
    }

    func deleteThreads(ids: [UUID]) async throws {
        for id in ids {
            let req = try request("messages/\(id.uuidString)", method: "DELETE")
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func archiveThreads(ids: [UUID]) async throws {
        struct Move: Encodable { var destinationId: String }
        let body = try JSONEncoder().encode(Move(destinationId: "archive"))
        for id in ids {
            var req = try request("messages/\(id.uuidString)/move", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func markRead(ids: [UUID], read: Bool) async throws {
        struct Patch: Encodable { var isRead: Bool }
        let body = try JSONEncoder().encode(Patch(isRead: read))
        for id in ids {
            let req = try request("messages/\(id.uuidString)", method: "PATCH", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func starThreads(ids: [UUID], starred: Bool) async throws {
        struct Patch: Encodable { var flag: Flag }
        struct Flag: Encodable { var flagStatus: String }
        let body = try JSONEncoder().encode(Patch(flag: .init(flagStatus: starred ? "flagged" : "notFlagged")))
        for id in ids {
            let req = try request("messages/\(id.uuidString)", method: "PATCH", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func searchThreads(query: String) async throws -> [EmailThread] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let req = try request("messages?$search=\"\(encoded)\"&$top=50")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GraphMessageList.self, from: data)
        return list.value.map { $0.toEmailThread(accountID: account.id) }
    }

    func fetchSpam(limit: Int) async throws -> [EmailThread] {
        let req = try request("mailFolders/junkemail/messages?$top=\(limit)")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(GraphMessageList.self, from: data)
        return list.value.map { $0.toEmailThread(accountID: account.id) }
    }

    func unsubscribe(from message: EmailMessage) async throws {
        try await UnsubscribeService.shared.unsubscribe(from: message, via: account)
    }

    func moveToSpam(ids: [UUID]) async throws {
        struct Move: Encodable { var destinationId: String }
        let body = try JSONEncoder().encode(Move(destinationId: "junkemail"))
        for id in ids {
            let req = try request("messages/\(id.uuidString)/move", method: "POST", body: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

// MARK: - Graph response shapes

private struct GraphMessageList: Decodable { var value: [GraphMessage] }

private struct GraphMessage: Decodable {
    var id: String
    var subject: String?
    var bodyPreview: String?
    var body: GraphBody?
    var from: GraphRecipient?
    var toRecipients: [GraphRecipient]?
    var receivedDateTime: String?
    var isRead: Bool?
    var flag: GraphFlag?

    struct GraphBody: Decodable { var content: String?; var contentType: String? }
    struct GraphRecipient: Decodable { var emailAddress: GraphAddress? }
    struct GraphAddress: Decodable { var name: String?; var address: String? }
    struct GraphFlag: Decodable { var flagStatus: String? }

    func toEmailMessage(accountID: UUID) -> EmailMessage {
        let fromAddr = EmailAddress(name: from?.emailAddress?.name ?? "",
                                   address: from?.emailAddress?.address ?? "")
        let bodyText = body?.content ?? bodyPreview ?? ""
        let links = HTMLLinkExtractor.extract(from: bodyText)
        return EmailMessage(
            id: UUID(), remoteID: id, accountID: accountID,
            from: fromAddr, to: [], cc: [],
            subject: subject ?? "", bodyPlain: bodyText, bodyHTML: "",
            date: ISO8601DateFormatter().date(from: receivedDateTime ?? "") ?? Date(),
            isRead: isRead ?? true,
            isStarred: flag?.flagStatus == "flagged",
            labels: [], links: links,
            unsubscribeURL: nil, unsubscribeEmail: nil, calendarInvite: nil
        )
    }

    func toEmailThread(accountID: UUID) -> EmailThread {
        let msg = toEmailMessage(accountID: accountID)
        return EmailThread(
            id: UUID(), remoteThreadID: id, accountID: accountID,
            subject: msg.subject, participants: [msg.from],
            messages: [msg], latestDate: msg.date,
            isRead: msg.isRead, isStarred: msg.isStarred,
            labels: [], snippet: bodyPreview ?? ""
        )
    }
}
