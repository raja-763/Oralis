import Foundation

/// Handles unsubscribing from mailing lists via:
/// 1. The List-Unsubscribe-Post header (one-click RFC 8058)
/// 2. A GET request to the unsubscribe URL
/// 3. Sending an email to the unsubscribe address
enum UnsubscribeResult {
    case unsubscribed              // confirmed: one-click accepted, or the page said so
    case requestSent               // an unsubscribe email was sent to the sender
    case followedLink(String)      // clicked through the sender's page; no clear confirmation
    case nothingWorked(String)     // the page had nothing to click
}

/// Unsubscribes entirely in the background: follows the link in the email and clicks through it
/// in a hidden page, or sends the unsubscribe email, whichever the sender uses.
final class UnsubscribeService {
    static let shared = UnsubscribeService()

    func unsubscribe(from message: EmailMessage, via account: EmailAccount) async throws -> UnsubscribeResult {
        // 1. Sender supports RFC 8058 one-click: a POST unsubscribes without any page.
        if message.unsubscribeOneClick, let url = message.unsubscribeURL, await tryOneClickPost(url: url) {
            oralisLog("unsubscribe: one-click accepted")
            return .unsubscribed
        }

        // 2. Follow the unsubscribe link and click through it in a hidden page.
        var pageOutcome: UnsubscribeBrowser.Outcome?
        if let link = message.unsubscribeURL ?? message.bodyUnsubscribeLink {
            oralisLog("unsubscribe: following the sender's link in the background")
            pageOutcome = await UnsubscribeBrowser().run(link)
            if case .confirmed = pageOutcome {
                oralisLog("unsubscribe: page confirmed")
                return .unsubscribed
            }
        }

        // 3. The sender's protocol is an email: send it (also used when the page was unclear).
        if let email = message.unsubscribeEmail {
            try await sendUnsubscribeEmail(to: email, from: account,
                                           subject: message.unsubscribeEmailSubject ?? "Unsubscribe",
                                           originalSubject: message.subject)
            oralisLog("unsubscribe: request email sent")
            return .requestSent
        }

        switch pageOutcome {
        case .clicked(let summary)?: return .followedLink(summary)
        case .noAction(let summary)?: return .nothingWorked(summary)
        default: throw OralisError.unsubscribeFailed("This email has no unsubscribe link or address.")
        }
    }

    // MARK: - One-click POST (RFC 8058)

    private func tryOneClickPost(url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "List-Unsubscribe=One-Click".data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse
        else {
            oralisLog("unsubscribe: one-click POST to \(url.host ?? "?") got no response")
            return false
        }
        let body = String(data: data.prefix(2000), encoding: .utf8) ?? ""
        oralisLog("unsubscribe: one-click POST to \(url.host ?? "?") returned HTTP \(http.statusCode), \(data.count) bytes\(UnsubscribeBrowser.looksUnsubscribed(body) ? ", page says unsubscribed" : "")")
        return (200...299).contains(http.statusCode)
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
