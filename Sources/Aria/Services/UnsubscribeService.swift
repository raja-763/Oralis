import Foundation

/// Handles unsubscribing from mailing lists via:
/// 1. The List-Unsubscribe-Post header (one-click RFC 8058)
/// 2. A GET request to the unsubscribe URL
/// 3. Sending an email to the unsubscribe address
enum UnsubscribeResult {
    case unsubscribed          // the sender accepted a one-click request
    case requestSent           // an unsubscribe email was sent to the sender
    case needsPage(URL)        // the sender's page must be opened and confirmed
}

final class UnsubscribeService {
    static let shared = UnsubscribeService()

    /// Only a one-click POST that the sender accepted, or a request email actually sent,
    /// counts as done. A plain web page needs the person to confirm, so it is handed back.
    func unsubscribe(from message: EmailMessage, via account: EmailAccount) async throws -> UnsubscribeResult {
        // 1. Sender supports RFC 8058 one-click: a POST unsubscribes without a page.
        if message.unsubscribeOneClick, let url = message.unsubscribeURL, await tryOneClickPost(url: url) {
            oralisLog("unsubscribe: one-click accepted")
            return .unsubscribed
        }
        // 2. Ask by email, as the sender's header describes.
        if let email = message.unsubscribeEmail {
            try await sendUnsubscribeEmail(to: email, from: account,
                                           subject: message.unsubscribeEmailSubject ?? "Unsubscribe",
                                           originalSubject: message.subject)
            oralisLog("unsubscribe: request email sent")
            return .requestSent
        }
        // 3. A web page (from the header, or a link in the email) that needs a confirming click.
        if let page = message.unsubscribeURL ?? message.bodyUnsubscribeLink {
            oralisLog("unsubscribe: needs the sender's page")
            return .needsPage(page)
        }
        throw OralisError.unsubscribeFailed("This email has no unsubscribe option.")
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

    // MARK: - Send unsubscribe email

    private func sendUnsubscribeEmail(to address: String, from account: EmailAccount,
                                       subject: String, originalSubject: String) async throws {
        let service = EmailServiceFactory.service(for: account)
        let draft = DraftMessage(
            to: [EmailAddress(name: "", address: address)],
            subject: subject,
            body: "Please unsubscribe me from this mailing list.\n\nOriginal subject: \(originalSubject)"
        )
        try await service.sendMessage(draft)
    }
}
