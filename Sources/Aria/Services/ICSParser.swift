import Foundation

/// Reads the first event out of an iCalendar (.ics) invite.
enum ICSParser {

    static func parse(_ ics: String) -> CalendarInvite? {
        let lines = unfold(ics)
        var inEvent = false
        var props: [String: (params: [String: String], value: String)] = [:]
        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { inEvent = true; continue }
            if upper == "END:VEVENT" { break }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let pieces = head.split(separator: ";").map(String.init)
            guard let name = pieces.first?.uppercased() else { continue }
            var params: [String: String] = [:]
            for p in pieces.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            if props[name] == nil { props[name] = (params, value) }
        }
        guard let start = props["DTSTART"].flatMap({ date($0.value, params: $0.params) }) else { return nil }
        let allDay = (props["DTSTART"]?.params["VALUE"] ?? "").uppercased() == "DATE" || (props["DTSTART"]?.value.count == 8)
        var end = props["DTEND"].flatMap { date($0.value, params: $0.params) } ?? start.addingTimeInterval(allDay ? 0 : 3600)
        // In an invite an all-day event ends the day after its last day; the calendar wants the last day.
        if allDay, let dtend = props["DTEND"], let d = date(dtend.value, params: dtend.params) {
            end = max(start, Calendar.current.date(byAdding: .day, value: -1, to: d) ?? start)
        }

        let organizerValue = props["ORGANIZER"]?.value ?? ""
        let organizerAddress = organizerValue.lowercased().hasPrefix("mailto:") ? String(organizerValue.dropFirst(7)) : organizerValue
        let organizer = EmailAddress(name: props["ORGANIZER"]?.params["CN"] ?? "", address: organizerAddress)

        let description = unescape(props["DESCRIPTION"]?.value ?? "")
        let location = unescape(props["LOCATION"]?.value ?? "")
        let meeting = meetingLink(in: [props["URL"]?.value ?? "", location, description])

        return CalendarInvite(
            title: unescape(props["SUMMARY"]?.value ?? "Meeting"),
            startDate: start, endDate: end,
            organizer: organizer, location: location, meetingURL: meeting,
            icsData: Data(ics.utf8), isAllDay: allDay
        )
    }

    /// Joins continuation lines (a line starting with a space or tab continues the previous one).
    private static func unfold(_ ics: String) -> [String] {
        var result: [String] = []
        for raw in ics.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
         .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func date(_ value: String, params: [String: String]) -> Date? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if v.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f.date(from: v)
        }
        f.timeZone = params["TZID"].flatMap { TimeZone(identifier: $0) } ?? .current
        if v.contains("T") {
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            return f.date(from: v)
        }
        f.dateFormat = "yyyyMMdd"   // all-day event
        return f.date(from: v)
    }

    private static func meetingLink(in texts: [String]) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"]
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, let host = url.host, hosts.contains(where: { host.contains($0) }) { return url }
            }
        }
        return nil
    }
}
