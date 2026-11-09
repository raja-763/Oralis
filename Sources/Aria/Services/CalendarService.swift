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
            throw AriaError.notAuthenticated
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
}
