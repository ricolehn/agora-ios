import Foundation

/// List rules shared by the start page and the events screen (same as web and Android).
enum EventRules {
    /// "Termine": appointments, plus events the user takes part in.
    static func showsInTermine(_ event: AgoraEvent, user: User, today: String) -> Bool {
        if event.isPast(today: today) { return false }
        if event.isTermin { return true }
        if event.requiresRegistration { return event.isRegistered || event.isWaitlisted || event.hasMyDuty(user) }
        // Pinned highlights live on the events tab
        if event.isPinned { return event.hasMyDuty(user) }
        return true
    }

    /// A multi-day event once per remaining day (from today on), others once on their start day.
    static func days(of events: [AgoraEvent], today: String) -> [EventDay] {
        events.flatMap { event -> [EventDay] in
            guard event.isMultiDay, event.endDate > event.date else { return [EventDay(event: event, day: event.date)] }
            let first = max(event.date, today)
            return Day.range(first, event.endDate).map { EventDay(event: event, day: $0) }
        }
        .sorted { $0.day != $1.day ? $0.day < $1.day : $0.event.startTime < $1.event.startTime }
    }

    static func matches(_ event: AgoraEvent, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [event.title, event.location, event.description].contains { $0.localizedCaseInsensitiveContains(needle) }
            || event.duties.contains { $0.roleName.localizedCaseInsensitiveContains(needle) }
    }

    /// Events tab: real events and pinned highlights.
    static func showsInEvents(_ event: AgoraEvent) -> Bool { !event.isTermin || event.isPinned }

    static func chronological(_ a: AgoraEvent, _ b: AgoraEvent) -> Bool {
        a.date != b.date ? a.date < b.date : a.startTime < b.startTime
    }

    /// Start page "Deine Dienste": upcoming events with a duty the user holds (personally or via a group).
    static func myDutyEvents(_ events: [AgoraEvent], user: User, today: String) -> [AgoraEvent] {
        events.filter { $0.lastDay >= today && ($0.myConfirmedDuty(user) != nil || $0.myGroupDuty(user) != nil) }
            .sorted(by: chronological)
    }

    /// Groups day entries by month ("2026-10") in order.
    static func byMonth<T>(_ items: [T], day: (T) -> String) -> [MonthGroup<T>] {
        var result: [MonthGroup<T>] = []
        for item in items {
            let month = Day.month(day(item))
            if let last = result.indices.last, result[last].month == month {
                result[last].items.append(item)
            } else {
                result.append(MonthGroup(month: month, items: [item]))
            }
        }
        return result
    }
}

/// Entries of one month ("2026-10").
struct MonthGroup<T>: Identifiable {
    let month: String
    var items: [T]
    var id: String { month }
}

/// One day of an event in the Termine list.
struct EventDay: Identifiable, Hashable, Sendable {
    let event: AgoraEvent
    let day: String
    var id: String { "\(event.id)-\(day)" }
}

/// The one badge a list card shows (first match wins).
enum EventBadge: Hashable, Sendable {
    case duty(String)
    case requestOpen
    case waitlist
    case registered
    case full
    case openDuties(Int)

    static func of(_ event: AgoraEvent, user: User, showRegistered: Bool = true) -> EventBadge? {
        if let duty = event.myConfirmedDuty(user) { return .duty(duty.role) }
        if let duty = event.myGroupDuty(user) { return .duty(duty.role) }
        if event.myOpenRequest(user) != nil { return .requestOpen }
        if event.isWaitlisted { return .waitlist }
        if event.isRegistered { return showRegistered ? .registered : nil }
        if event.requiresRegistration && event.isFull { return .full }
        if event.canAccessDutyPlan && event.openDutySlots > 0 { return .openDuties(event.openDutySlots) }
        return nil
    }
}

/// Places without a map: online meetings.
enum Places {
    static func isOnline(_ location: String) -> Bool {
        let lower = location.lowercased()
        return ["online", "zoom", "teams", "meet.google", "http://", "https://", "discord", "jitsi"].contains { lower.contains($0) }
    }
}
