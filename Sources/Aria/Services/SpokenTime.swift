import Foundation

/// Dates and times worded the way a person says them aloud, in the Mac's own time zone:
/// "tomorrow at 3 PM", "today at 6:30 PM", "Wednesday, November 18 at noon".
enum SpokenTime {

    /// "3 PM", "3:30 PM", "noon", "midnight".
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        if minute == 0 && hour == 12 { return "noon" }
        if minute == 0 && hour == 0 { return "midnight" }
        let suffix = hour < 12 ? "AM" : "PM"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(h12) \(suffix)" : "\(h12):\(String(format: "%02d", minute)) \(suffix)"
    }

    /// "today", "tomorrow", "yesterday", or "Wednesday, November 18" (with the year when it
    /// is not this year).
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "EEEE, MMMM d" : "EEEE, MMMM d, yyyy"
        return f.string(from: date)
    }

    /// "tomorrow at 3 PM". For an all-day event: "Wednesday, November 18, all day".
    static func when(_ date: Date, allDay: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        allDay ? "\(day(date, now: now, calendar: calendar)), all day"
                : "\(day(date, now: now, calendar: calendar)) at \(time(date, calendar: calendar))"
    }

    /// "tomorrow from 3 PM to 3:30 PM".
    static func range(_ start: Date, _ end: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard calendar.isDate(start, inSameDayAs: end) else {
            return "\(when(start, now: now, calendar: calendar)) until \(when(end, now: now, calendar: calendar))"
        }
        return "\(day(start, now: now, calendar: calendar)) from \(time(start, calendar: calendar)) to \(time(end, calendar: calendar))"
    }

    /// For the AI: the exact moment "now", so "tomorrow at 3" lands on the right day and hour.
    static func nowForAI(now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return "\(f.string(from: now)) (\(calendar.timeZone.identifier), local time zone of the user; ISO date today: \(isoDay(now, calendar)))"
    }

    private static func isoDay(_ d: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
