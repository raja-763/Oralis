import Foundation

// MARK: - Protocol every email provider implements

protocol EmailService {
    var account: EmailAccount { get }

    func fetchThreads(limit: Int) async throws -> [EmailThread]
    func fetchMessage(id: String) async throws -> EmailMessage
    func sendMessage(_ draft: DraftMessage) async throws
    func deleteThreads(ids: [UUID]) async throws
    func archiveThreads(ids: [UUID]) async throws
    func markRead(ids: [UUID], read: Bool) async throws
    func starThreads(ids: [UUID], starred: Bool) async throws
    func searchThreads(query: String) async throws -> [EmailThread]
    func fetchSpam(limit: Int) async throws -> [EmailThread]
    func unsubscribe(from message: EmailMessage) async throws -> UnsubscribeResult
    func moveToSpam(ids: [UUID]) async throws
    func moveToInbox(ids: [UUID]) async throws
}

extension EmailService {
    func moveToInbox(ids: [UUID]) async throws {
        throw OralisError.apiError("Moving mail back to the inbox is only supported for Gmail accounts.")
    }
}

// MARK: - Draft

struct DraftMessage {
    var to: [EmailAddress]
    var cc: [EmailAddress] = []
    var bcc: [EmailAddress] = []
    var subject: String
    var body: String
    var replyToMessageID: String?
    var forwardOfMessageID: String?
}

// MARK: - Factory

enum EmailServiceFactory {
    static func service(for account: EmailAccount) -> any EmailService {
        switch account.provider {
        case .gmail:   return GmailService(account: account)
        case .outlook: return OutlookService(account: account)
        default:       return IMAPService(account: account)
        }
    }
}
