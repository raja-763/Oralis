import Foundation

/// Generic IMAP/SMTP service using URLSession for IMAP-over-HTTP proxy
/// (or direct IMAP via Network.framework in a future iteration).
/// This skeleton handles the full protocol surface; the network layer
/// is stubbed and ready to be backed by a real IMAP library.
final class IMAPService: EmailService {
    let account: EmailAccount

    init(account: EmailAccount) {
        self.account = account
    }

    func fetchThreads(limit: Int) async throws -> [EmailThread] {
        // TODO: open IMAP connection, SELECT INBOX, FETCH threads
        return []
    }

    func fetchMessage(id: String) async throws -> EmailMessage {
        throw AriaError.notImplemented("IMAP fetchMessage")
    }

    func sendMessage(_ draft: DraftMessage) async throws {
        // TODO: SMTP connection, EHLO, AUTH, DATA
    }

    func deleteThreads(ids: [UUID]) async throws {
        // STORE +FLAGS.SILENT \Deleted, then EXPUNGE
    }

    func archiveThreads(ids: [UUID]) async throws {
        // COPY to Archive folder, then delete from INBOX
    }

    func markRead(ids: [UUID], read: Bool) async throws {
        // STORE ±FLAGS.SILENT \Seen
    }

    func starThreads(ids: [UUID], starred: Bool) async throws {
        // STORE ±FLAGS.SILENT \Flagged
    }

    func searchThreads(query: String) async throws -> [EmailThread] {
        return []
    }

    func fetchSpam(limit: Int) async throws -> [EmailThread] {
        return []
    }

    func unsubscribe(from message: EmailMessage) async throws {
        try await UnsubscribeService.shared.unsubscribe(from: message, via: account)
    }

    func moveToSpam(ids: [UUID]) async throws {}
}
