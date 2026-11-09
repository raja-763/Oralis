import Foundation

struct EmailThread: Identifiable, Codable, Equatable {
    let id: UUID
    var remoteThreadID: String
    var accountID: UUID
    var subject: String
    var participants: [EmailAddress]
    var messages: [EmailMessage]
    var latestDate: Date
    var isRead: Bool
    var isStarred: Bool
    var labels: [String]
    var snippet: String           // one-line preview

    var latestMessage: EmailMessage? { messages.last }

    var accessibilityLabel: String {
        let readState = isRead ? "" : "Unread. "
        let count = messages.count > 1 ? "\(messages.count) messages. " : ""
        let dateStr = RelativeDateTimeFormatter().localizedString(for: latestDate, relativeTo: Date())
        let from = participants.first?.display ?? ""
        return "\(readState)\(count)\(from), \(subject), \(snippet), \(dateStr)"
    }
}
