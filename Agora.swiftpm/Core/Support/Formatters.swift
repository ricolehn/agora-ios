import Foundation

/// Calendar days as the backend stores them ("yyyy-MM-dd", compared as text) in the device's time zone.
enum Day {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func today(_ now: Date = Date()) -> String { isoFormatter.string(from: now) }

    static func string(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func date(_ day: String) -> Date? {
        guard day.count >= 10 else { return nil }
        return isoFormatter.date(from: String(day.prefix(10)))
    }

    static func adding(_ days: Int, to day: String) -> String? {
        guard let date = date(day), let moved = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(moved)
    }

    /// Every day from [start] to [end] inclusive (at most a year).
    static func range(_ start: String, _ end: String) -> [String] {
        guard var current = date(start), let last = date(end), current <= last else { return [start] }
        var days: [String] = []
        while current <= last, days.count < 366 {
            days.append(string(current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// "2026-10" of a day, for month groups.
    static func month(_ day: String) -> String { String(day.prefix(7)) }
}

/// Display formats in the app language (German by default, like the web app).
enum Formats {
    static var locale: Locale { Locale.autoupdatingCurrent.language.languageCode?.identifier == "en" ? Locale(identifier: "en_GB") : Locale(identifier: "de_DE") }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// "Mittwoch, 30. September 2026"
    static func longDay(_ day: String) -> String {
        guard let date = Day.date(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    /// "30.09.2026"
    static func shortDay(_ day: String) -> String {
        guard let date = Day.date(day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// "30. Sep. 2026"
    static func mediumDay(_ day: String) -> String {
        guard let date = Day.date(day) else { return day }
        return formatter("dMMMyyyy").string(from: date)
    }

    /// "Oktober 2026" for a "2026-10" month key.
    static func monthYear(_ month: String) -> String {
        guard let date = Day.date(month + "-01") else { return month }
        return formatter("MMMMyyyy").string(from: date)
    }

    /// "Samstag, 3. Oktober" (start page greeting).
    static func greetingDate(_ date: Date = Date()) -> String { formatter("EEEEdMMMM").string(from: date) }

    /// "Heute", "Morgen", the weekday within a week, else "Sa., 17. Okt." (start page "Als Nächstes").
    static func relativeDay(_ day: String, today: String = Day.today()) -> String {
        if day <= today { return String(localized: "Heute") }
        guard let date = Day.date(day), let start = Day.date(today) else { return day }
        let days = Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0
        if days == 1 { return String(localized: "Morgen") }
        if days < 7 { return formatter("EEEE").string(from: date) }
        return formatter("EEEdMMM").string(from: date)
    }

    /// Calendar leaf parts: "OKT", "17", "Sa".
    static func leaf(_ day: String) -> (month: String, day: String, weekday: String) {
        guard let date = Day.date(day) else { return ("", "?", "") }
        let month = formatter("MMM").string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
        let weekday = formatter("EEE").string(from: date).replacingOccurrences(of: ".", with: "")
        let number = String(Calendar.current.component(.day, from: date))
        return (month, number, weekday)
    }

    /// "17.–19. Okt." or "30. Sep. – 2. Okt." (multi-day events).
    static func span(_ start: String, _ end: String) -> String {
        guard let first = Day.date(start), let last = Day.date(end) else { return start }
        let calendar = Calendar.current
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(calendar.component(.day, from: first)).–\(formatter("dMMM").string(from: last))"
        }
        if calendar.isDate(first, equalTo: last, toGranularity: .year) {
            return "\(formatter("dMMM").string(from: first)) – \(formatter("dMMM").string(from: last))"
        }
        return "\(mediumDay(start)) – \(mediumDay(end))"
    }

    static var isGerman: Bool { locale.language.languageCode?.identifier == "de" }

    /// "10:00 – 11:30", "10:00" or "" without a start time.
    static func timeRange(_ start: String, _ end: String) -> String {
        let from = start.trimmingCharacters(in: .whitespaces)
        let to = end.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { return "" }
        return to.isEmpty ? from : "\(from) – \(to)"
    }

    /// "10:00 – 11:30 Uhr" (German) for list rows.
    static func clockRange(_ start: String, _ end: String) -> String {
        let range = timeRange(start, end)
        return range.isEmpty || !isGerman ? range : range + " Uhr"
    }

    /// "Mi., 30. Sept. 2026"
    static func compactDay(_ day: String) -> String {
        guard let date = Day.date(day) else { return day }
        return formatter("EEEdMMMyyyy").string(from: date)
    }

    /// "17. – 19. Okt. 2026", "30. Sept. – 2. Okt. 2026" or across years "30.12.2026 – 02.01.2027".
    static func compactSpan(_ start: String, _ end: String) -> String {
        guard let first = Day.date(start), let last = Day.date(end) else { return start }
        let calendar = Calendar.current
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(calendar.component(.day, from: first)). – \(formatter("dMMMyyyy").string(from: last))"
        }
        if calendar.isDate(first, equalTo: last, toGranularity: .year) {
            return "\(formatter("dMMM").string(from: first)) – \(formatter("dMMMyyyy").string(from: last))"
        }
        return "\(shortDay(start)) – \(shortDay(end))"
    }

    /// Detail view: span for multi-day events, else "Mi., 30. Sept. 2026 · 10:00 – 11:30 Uhr" or "… · Ganztägig".
    static func eventWhen(_ event: AgoraEvent) -> String {
        if event.isMultiDay { return compactSpan(event.date, event.endDate) }
        let time = clockRange(event.startTime, event.endTime)
        return "\(compactDay(event.date)) · \(time.isEmpty ? (isGerman ? "Ganztägig" : "All day") : time)"
    }

    /// List rows: span for multi-day events, "Ganztägig" without a time, else the clock range.
    static func eventRowWhen(_ event: AgoraEvent) -> String {
        if event.isMultiDay { return span(event.date, event.endDate) }
        let time = clockRange(event.startTime, event.endTime)
        return time.isEmpty ? (isGerman ? "Ganztägig" : "All day") : time
    }

    /// "850,00 €"
    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "EUR").locale(locale))
    }

    /// "+ 12,50 €" / "- 12,50 €"
    static func signedMoney(_ amount: Double, income: Bool) -> String { (income ? "+ " : "- ") + money(abs(amount)) }

    /// Paid-until month ("Oktober 2026"). The server sends the instant of a server-local midnight: shifted by
    /// 12 hours and read in UTC it lands on the right month in every time zone.
    static func paidUntilMonth(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let instant = timestamp(raw) else { return monthYear(Day.month(raw)) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let shifted = instant.addingTimeInterval(12 * 3600)
        let parts = utc.dateComponents([.year, .month], from: shifted)
        guard let year = parts.year, let month = parts.month else { return nil }
        return monthYear(String(format: "%04d-%02d", year, month))
    }

    /// "21.09.26, 16:16" for epoch milliseconds (request timestamps).
    static func dateTime(millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    // MARK: Timestamps ("2026-10-02 04:39:52.971Z" from PocketBase, or ISO 8601)

    static func timestamp(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        guard !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        return Day.date(text)
    }

    /// "14:05" today, "Gestern", "Mo" within a week, else "30.09."
    static func chatTime(_ raw: String, now: Date = Date()) -> String {
        guard let date = timestamp(raw) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return formatter("HHmm").string(from: date) }
        if calendar.isDateInYesterday(date) { return locale.language.languageCode?.identifier == "de" ? "Gestern" : "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 { return formatter("EEE").string(from: date) }
        return formatter("ddMM").string(from: date)
    }

    /// "14:05" for a chat bubble.
    static func clock(_ raw: String) -> String {
        guard let date = timestamp(raw) else { return "" }
        return formatter("HHmm").string(from: date)
    }

    /// Day separator in chats: "Heute", "Gestern" or "Mittwoch, 30. September".
    static func chatDay(_ raw: String) -> String {
        guard let date = timestamp(raw) else { return "" }
        let calendar = Calendar.current
        let german = locale.language.languageCode?.identifier == "de"
        if calendar.isDateInToday(date) { return german ? "Heute" : "Today" }
        if calendar.isDateInYesterday(date) { return german ? "Gestern" : "Yesterday" }
        return formatter("EEEEdMMMM").string(from: date)
    }
}
