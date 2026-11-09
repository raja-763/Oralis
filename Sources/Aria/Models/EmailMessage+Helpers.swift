import Foundation

extension EmailMessage {
    static func placeholder(accountID: UUID) -> EmailMessage {
        EmailMessage(
            id: UUID(), remoteID: "", accountID: accountID,
            from: EmailAddress(name: "", address: ""),
            to: [], cc: [], subject: "", bodyPlain: "", bodyHTML: "",
            date: Date(), isRead: true, isStarred: false,
            labels: [], links: [],
            unsubscribeURL: nil, unsubscribeEmail: nil, calendarInvite: nil
        )
    }
}

extension DraftMessage {
    /// Very minimal RFC 2822 MIME serialisation (plain text only).
    func toMIME() -> String {
        let toStr  = to.map(\.address).joined(separator: ", ")
        let ccStr  = cc.isEmpty ? "" : "Cc: \(cc.map(\.address).joined(separator: ", "))\r\n"
        return "To: \(toStr)\r\n\(ccStr)Subject: \(subject)\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n\(body)"
    }
}
