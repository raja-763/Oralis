import Foundation

/// IMAP/SMTP email service backed by IMAPClient (NWConnection + TLS).
final class IMAPService: EmailService {
    let account: EmailAccount

    init(account: EmailAccount) {
        self.account = account
    }

    // MARK: - Fetch

    func fetchThreads(limit: Int) async throws -> [EmailThread] {
        let (host, port) = imapCoords
        guard !host.isEmpty else { throw IMAPError.notConnected }

        let password = KeychainService.loadPassword(for: account.id) ?? ""
        guard !password.isEmpty else {
            throw OralisError.apiError("No password saved for \(account.emailAddress). Open Settings → Accounts to re-enter it.")
        }

        let client = IMAPClient()
        try await client.connect(host: host, port: port)
        try await client.login(username: account.emailAddress, password: password)
        let threads = try await client.fetchInbox(limit: limit)
        await client.logout()
        return threads
    }

    func fetchMessage(id: String) async throws -> EmailMessage {
        // Full-body fetch not yet implemented — callers receive body in fetchThreads preview
        throw OralisError.notImplemented("IMAP full fetchMessage")
    }

    // MARK: - Send (SMTP — not yet implemented; store draft locally)

    func sendMessage(_ draft: DraftMessage) async throws {
        // TODO: SMTP with STARTTLS
        throw OralisError.notImplemented("SMTP send — coming soon")
    }

    // MARK: - Mutations (mark read/delete/archive via IMAP commands)

    func deleteThreads(ids: [UUID]) async throws {
        // TODO: STORE +FLAGS.SILENT \Deleted, then EXPUNGE
    }

    func archiveThreads(ids: [UUID]) async throws {
        // TODO: COPY to Archive, delete from INBOX
    }

    func markRead(ids: [UUID], read: Bool) async throws {
        // TODO: STORE ±FLAGS.SILENT \Seen
    }

    func starThreads(ids: [UUID], starred: Bool) async throws {
        // TODO: STORE ±FLAGS.SILENT \Flagged
    }

    func searchThreads(query: String) async throws -> [EmailThread] {
        // TODO: IMAP SEARCH command
        return []
    }

    func fetchSpam(limit: Int) async throws -> [EmailThread] {
        return []
    }

    func unsubscribe(from message: EmailMessage) async throws -> UnsubscribeResult {
        try await UnsubscribeService.shared.unsubscribe(from: message, via: account)
    }

    func moveToSpam(ids: [UUID]) async throws {}

    // MARK: - Helpers

    private var imapCoords: (String, Int) {
        if !account.imapHost.isEmpty { return (account.imapHost, account.imapPort) }
        // Fall back to per-provider defaults
        switch account.provider {
        case .icloud:  return ("imap.mail.me.com",          993)
        case .gmail:   return ("imap.gmail.com",             993)
        case .outlook: return ("outlook.office365.com",      993)
        case .yahoo:   return ("imap.mail.yahoo.com",        993)
        default:       return ("",                             993)
        }
    }
}
