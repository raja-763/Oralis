import Foundation

// MARK: - EmailAddress

struct EmailAddress: Codable, Equatable, Hashable {
    var name: String
    var address: String

    var display: String { name.isEmpty ? address : "\(name) <\(address)>" }
}

// MARK: - EmailMessage

struct EmailMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var remoteID: String          // server-side UID / message-id
    var accountID: UUID

    var from: EmailAddress
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var subject: String
    var bodyPlain: String         // plain-text body
    var bodyHTML: String          // HTML body (empty if none)
    var date: Date
    var isRead: Bool
    var isStarred: Bool
    var labels: [String]          // Gmail labels / Outlook categories

    // Links found in the email body, extracted on fetch
    var links: [EmailLink]

    // Unsubscribe info parsed from List-Unsubscribe header
    var unsubscribeURL: URL?
    var unsubscribeEmail: String?
    var unsubscribeEmailSubject: String? = nil
    /// The sender supports RFC 8058 one-click unsubscribe (List-Unsubscribe-Post header).
    var unsubscribeOneClick: Bool = false

    // Calendar invite attachment, if present
    var calendarInvite: CalendarInvite?

    var accessibilityLabel: String {
        let readState = isRead ? "" : "Unread. "
        let dateStr = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        return "\(readState)\(from.display), \(subject), \(dateStr)"
    }

    var hasUnsubscribeOption: Bool {
        unsubscribeURL != nil || unsubscribeEmail != nil || bodyUnsubscribeLink != nil
    }

    /// A link in the body that looks like an unsubscribe page, for senders without the header.
    var bodyUnsubscribeLink: URL? {
        links.first { ($0.title + " " + $0.url.absoluteString).lowercased().contains("unsubscribe") }?.url
    }
}

// MARK: - EmailLink

struct EmailLink: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: URL
}

// MARK: - CalendarInvite

struct CalendarInvite: Codable, Equatable {
    var title: String
    var startDate: Date
    var endDate: Date
    var organizer: EmailAddress
    var location: String
    var meetingURL: URL?         // Zoom / Teams / Meet link
    var icsData: Data            // raw iCalendar data

    var accessibilityDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        var desc = "\(title), \(formatter.string(from: startDate))."
        if let url = meetingURL { desc += " Virtual meeting at \(url.host ?? url.absoluteString)." }
        return desc
    }
}
