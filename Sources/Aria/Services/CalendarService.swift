import EventKit
import Foundation

/// Reads and writes calendar events, primarily for accepting/declining
/// email invites and joining virtual meetings.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        // Never re-prompt: only ask when the user has not decided yet.
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined: break
        default: return false
        }
        return await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// A calendar that can take new events, even if no default calendar is set.
    private func writableCalendar() throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewEvents, cal.allowsContentModifications { return cal }
        if let cal = store.calendars(for: .event).first(where: \.allowsContentModifications) { return cal }
        throw OralisError.apiError("There is no calendar I can add events to. Open the Calendar app and make sure you have a calendar.")
    }

    /// Add an accepted invite to the user's calendar (once: the same invite is not added twice).
    func addInvite(_ invite: CalendarInvite) async throws {
        guard await requestAccess() else {
            throw OralisError.notAuthenticated
        }
        let window = store.predicateForEvents(withStart: invite.startDate.addingTimeInterval(-60),
                                              end: invite.startDate.addingTimeInterval(60), calendars: nil)
        if store.events(matching: window).contains(where: { $0.title == invite.title }) { return }
        let event = EKEvent(eventStore: store)
        event.title      = invite.title
        event.startDate  = invite.startDate
        event.endDate    = invite.endDate
        event.isAllDay   = invite.isAllDay
        event.location   = invite.location
        event.notes      = invite.meetingURL?.absoluteString
        event.calendar   = try writableCalendar()
        try store.save(event, span: .thisEvent)
    }

    /// Deletes events whose title contains `titleContains` (optionally only on one day).
    /// Returns a spoken description of each event removed.
    func deleteEvents(titleContains: String, on day: Date? = nil) async throws -> [String] {
        guard await requestAccess() else { throw OralisError.notAuthenticated }
        let cal = Calendar.current
        let start = day.map { cal.startOfDay(for: $0) } ?? cal.date(byAdding: .day, value: -30, to: Date())!
        let end = day.map { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0))! }
            ?? cal.date(byAdding: .day, value: 365, to: Date())!
        let wanted = titleContains.lowercased()
        let matches = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { ($0.title ?? "").lowercased().contains(wanted) && $0.calendar.allowsContentModifications }
            .sorted { $0.startDate < $1.startDate }
        var removed: [String] = []
        for event in matches.prefix(5) {
            let description = "\(event.title ?? "Untitled"), \(SpokenTime.when(event.startDate, allDay: event.isAllDay))"
            try store.remove(event, span: .thisEvent, commit: true)
            removed.append(description)
        }
        return removed
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
        event.calendar  = try writableCalendar()
        try store.save(event, span: .thisEvent)
    }

    /// Format events as a voice-readable summary.
    func formatEventSummary(_ events: [EKEvent]) -> String {
        guard !events.isEmpty else { return "No upcoming events in the next 7 days." }
        // Worded as it is said aloud: "tomorrow at 3 PM", "Wednesday, November 18 at 6 PM".
        let lines = events.prefix(10).map { event -> String in
            let when = event.isAllDay ? SpokenTime.when(event.startDate, allDay: true)
                                      : SpokenTime.range(event.startDate, event.endDate)
            return "– \(event.title ?? "Untitled"), \(when)"
        }
        return lines.joined(separator: "\n")
    }
}
