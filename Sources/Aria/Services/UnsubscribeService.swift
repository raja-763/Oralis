import Foundation

/// Handles unsubscribing from mailing lists via:
/// 1. The List-Unsubscribe-Post header (one-click RFC 8058)
/// 2. A GET request to the unsubscribe URL
/// 3. Sending an email to the unsubscribe address
final class UnsubscribeService {
    static let shared = UnsubscribeService()

    func unsubscribe(from message: EmailMessage, via account: EmailAccount) async throws {
        // Prefer one-click POST (RFC 8058) — most modern lists support this
        if let url = message.unsubscribeURL {
            if await tryOneClickPost(url: url) { return }
            if await tryGETUnsubscribe(url: url) { return }
        }

        // Fall back to sending an unsubscribe email
        if let email = message.unsubscribeEmail {
            try await sendUnsubscribeEmail(to: email, from: account, originalSubject: message.subject)
            return
        }

        throw OralisError.unsubscribeFailed("No unsubscribe method available for this email.")
    }

    // MARK: - One-click POST (RFC 8058)

    private func tryOneClickPost(url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "List-Unsubscribe=One-Click".data(using: .utf8)
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return false }
        return true
    }

    // MARK: - GET unsubscribe URL

    private func tryGETUnsubscribe(url: URL) async -> Bool {
        guard let (_, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return false }
        return true
    }

    // MARK: - Send unsubscribe email

    private func sendUnsubscribeEmail(to address: String, from account: EmailAccount,
                                       originalSubject: String) async throws {
        let service = EmailServiceFactory.service(for: account)
        let draft = DraftMessage(
            to: [EmailAddress(name: "", address: address)],
            subject: "Unsubscribe",
            body: "Please unsubscribe me from this mailing list.\n\nOriginal subject: \(originalSubject)"
        )
        try await service.sendMessage(draft)
    }
}
