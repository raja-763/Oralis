import EventKit
import Foundation

/// Reads and writes calendar events, primarily for accepting/declining
/// email invites and joining virtual meetings.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// Add an accepted invite to the user's calendar.
    func addInvite(_ invite: CalendarInvite) async throws {
        guard await requestAccess() else {
            throw OralisError.notAuthenticated
        }
        let event = EKEvent(eventStore: store)
        event.title      = invite.title
        event.startDate  = invite.startDate
        event.endDate    = invite.endDate
        event.location   = invite.location
        event.notes      = invite.meetingURL?.absoluteString
        event.calendar   = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }

    /// Fetch upcoming virtual meetings (events with a URL in notes or location).
    func upcomingVirtualMeetings(days: Int = 7) async throws -> [EKEvent] {
        guard await requestAccess() else { return [] }
        let now  = Date()
        let end  = Calendar.current.date(byAdding: .day, value: days, to: now)!
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: pred).filter { event in
            let combined = (event.notes ?? "") + (event.location ?? "")
            return combined.contains("zoom.us") || combined.contains("meet.google") ||
                   combined.contains("teams.microsoft") || combined.contains("webex")
        }
    }

    /// All upcoming events within `days` days, sorted by start date.
    func upcomingEvents(days: Int = 7) async throws -> [EKEvent] {
        guard await requestAccess() else { return [] }
        let now  = Date()
        let end  = Calendar.current.date(byAdding: .day, value: days, to: now)!
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    /// Create a new calendar event.
    func createEvent(title: String, startDate: Date, durationMinutes: Int, notes: String? = nil) async throws {
        guard await requestAccess() else { throw OralisError.notAuthenticated }
        let event = EKEvent(eventStore: store)
        event.title     = title
        event.startDate = startDate
        event.endDate   = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.notes     = notes
        event.calendar  = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
    }

    /// Format events as a voice-readable summary.
    func formatEventSummary(_ events: [EKEvent]) -> String {
        guard !events.isEmpty else { return "No upcoming events in the next 7 days." }
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .short
        let lines = events.prefix(10).map { "– \($0.title ?? "Untitled") on \(fmt.string(from: $0.startDate))" }
        return lines.joined(separator: "\n")
    }
}
