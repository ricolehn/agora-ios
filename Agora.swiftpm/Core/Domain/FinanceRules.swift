import Foundation

/// Ending / removing standing orders, ported from the web app (saveStandingOrderEnd) via the Android client, so all
/// clients write identical records. Days are "yyyy-MM-dd" and compared as text.
enum StandingOrders {
    /// Sets the end date of order [orderId]. Automatic payments of this order booked after that day are removed
    /// again (ending retroactively), the paid total follows, and an order whose end lies in the past is dropped.
    static func end(_ person: JSONValue, orderId: String, endDate: String, today: String) -> JSONValue {
        guard endDate.count >= 10 else { return person }
        let end = String(endDate.prefix(10))
        let autoPrefix = "auto_\(orderId)_"
        let payments = (person["payments"]?.arrayValue ?? []).filter { item in
            guard item.objectValue != nil else { return true }
            let isAuto = item["isAuto"]?.boolValue == true
            let paidOn = item["date"]?.text.map { String($0.prefix(10)) }
            let removed = isAuto && (item["id"]?.text ?? "").hasPrefix(autoPrefix) && paidOn.map { $0.count == 10 && $0 > end } == true
            return !removed
        }
        let orders = (person["standingOrders"]?.arrayValue ?? []).compactMap { item -> JSONValue? in
            guard item.objectValue != nil else { return item }
            if item["id"]?.text != orderId { return item }
            if end < today { return nil }
            var updated = item
            updated["endDate"] = .string(endDate)
            return updated
        }
        let total = payments.reduce(0.0) { $0 + ($1["amount"]?.amount ?? 0) }
        var result = person
        result["payments"] = .array(payments)
        result["standingOrders"] = .array(orders)
        result["totalPaid"] = .number(total)
        return result
    }

    static func remove(_ person: JSONValue, orderId: String) -> JSONValue {
        var result = person
        result["standingOrders"] = .array((person["standingOrders"]?.arrayValue ?? []).filter { $0["id"]?.text != orderId })
        return result
    }
}

/// Status history rewriting (`applyStatusChangeToHistory` in the web app), retroactive or in the future.
enum StatusHistory {
    private static func text(_ value: JSONValue?, _ key: String) -> String? {
        guard let text = value?[key]?.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    private static func entry(_ status: String, _ start: String, _ end: String?) -> JSONValue {
        var value: JSONValue = ["status": .string(status), "startDate": .string(start)]
        if let end { value["endDate"] = .string(end) }
        return value
    }

    static func apply(_ person: JSONValue, newStatus: String, changeDate: String) throws -> JSONValue {
        let memberSince = text(person, "originalMemberSince") ?? text(person, "memberSince") ?? changeDate
        if changeDate < memberSince {
            throw APIError(status: 400, message: "Änderungsdatum liegt vor Beginn der Mitgliedschaft.")
        }
        var result = person
        result["status"] = .string(newStatus)
        if changeDate <= memberSince {
            result["statusHistory"] = .array([entry(newStatus, memberSince, nil)])
            return result
        }
        var history: [JSONValue] = (person["statusHistory"]?.arrayValue ?? [])
            .filter { $0.objectValue != nil && (text($0, "startDate") ?? memberSince) < changeDate }
            .map { item in
                if let end = text(item, "endDate"), end <= changeDate { return item }
                var closed = item
                closed["endDate"] = .string(changeDate)
                return closed
            }
        let lastEnd = history.last.flatMap { text($0, "endDate") }
        if history.isEmpty || (lastEnd.map { $0 < changeDate } ?? false) {
            let priorStart = lastEnd ?? memberSince
            if priorStart < changeDate {
                history.append(entry(text(person, "status") ?? "vollverdiener", priorStart, changeDate))
            }
        }
        history.append(entry(newStatus, changeDate, nil))
        result["statusHistory"] = .array(history)
        return result
    }
}

/// One line of the finance timeline ("Verlauf"): payments and status changes, newest first.
struct TimelineEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case payment(amount: Double, note: String), status(String) }

    let id: String
    let date: String
    let kind: Kind

    static func build(for person: Person) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for (index, item) in person.statusHistory.enumerated() where !item.startDate.isEmpty {
            entries.append(TimelineEntry(id: "s\(index)", date: item.startDate, kind: .status(item.status)))
        }
        // The current status as of the end of the history, or the start of the membership without one
        let currentSince = person.statusHistory.isEmpty
            ? (person.originalMemberSince.isEmpty ? person.memberSince : person.originalMemberSince)
            : (person.statusHistory.last?.endDate ?? "")
        if !currentSince.isEmpty, !person.status.isEmpty {
            entries.append(TimelineEntry(id: "current", date: currentSince, kind: .status(person.status)))
        }
        for (index, payment) in person.payments.enumerated() where !payment.date.isEmpty {
            entries.append(TimelineEntry(id: "p\(index)-\(payment.id)", date: payment.date, kind: .payment(amount: payment.amount, note: payment.description)))
        }
        return entries.sorted { $0.date > $1.date }
    }
}
