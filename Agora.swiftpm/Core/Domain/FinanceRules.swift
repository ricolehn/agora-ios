import Foundation

/// JSON helpers for person records.
enum PersonRecord {
    static func append(_ person: JSONValue, to key: String, _ item: JSONValue) -> JSONValue {
        var result = person
        result[key] = .array((person[key]?.arrayValue ?? []) + [item])
        return result
    }

    static func addingToTotal(_ person: JSONValue, _ added: Double) -> JSONValue {
        var result = person
        result["totalPaid"] = .number((person["totalPaid"]?.amount ?? 0) + added)
        return result
    }
}

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

/// What an approved request books, ported from the web app (assets/finance.js) via the Android client, so all clients
/// write identical records. Every booking carries the id "req_<request id>": approving the request again finds it and
/// adds nothing, also when another app approved it first.
enum RequestBookings {
    static func id(_ request: FinanceRequest) -> String { "req_\(request.id)" }

    private static func contains(_ list: JSONValue?, id: String) -> Bool { (list?.arrayValue ?? []).contains { $0["id"]?.text == id } }
    private static func removing(_ id: String, from list: JSONValue?) -> JSONValue { .array((list?.arrayValue ?? []).filter { $0["id"]?.text != id }) }

    /// The member's record with the approved [request] booked ([amount]: its amount, unused for a status change).
    static func apply(_ person: JSONValue, request: FinanceRequest, amount: Double) throws -> JSONValue {
        let id = id(request)
        let date = request.field("date") ?? ""
        let note = request.field("note").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch request.type {
        case "payment":
            if contains(person["payments"], id: id) { return person }
            return PersonRecord.addingToTotal(PersonRecord.append(person, to: "payments", [
                "id": .string(id), "amount": .number(amount), "date": .string(date), "description": .string(note ?? "Zahlung (Genehmigt)")
            ]), amount)
        case "standing_order":
            if contains(person["standingOrders"], id: id) { return person }
            return PersonRecord.append(person, to: "standingOrders", [
                "id": .string(id), "amount": .number(amount), "startDate": .string(date),
                "note": .string(note ?? "Dauerauftrag (Genehmigt)"), "lastAutoPayment": .null
            ])
        case "status":
            // Same history rewrite as a treasurer status change, like the web app (applied again, it changes nothing)
            return try StatusHistory.apply(person, newStatus: request.field("newStatus") ?? "", changeDate: date)
        default:
            return person
        }
    }

    /// The expense list with the approved expense [request] (the requester is the issuer), nil when it is booked already.
    static func addingExpense(_ expenses: [JSONValue], request: FinanceRequest, amount: Double) -> [JSONValue]? {
        let id = id(request)
        if contains(.array(expenses), id: id) { return nil }
        return expenses + [[
            "id": .string(id), "amount": .number(amount), "description": .string(request.field("description") ?? ""),
            "issuer": .string(request.personName), "date": .string(request.field("date") ?? ""), "receipt": request.data["receipt"] ?? .null
        ]]
    }

    /// The record without what approving [request] booked, for an approval that lost against a rejection made at the
    /// same moment: its payment or standing order goes, a status change goes back to the record [before] it.
    static func removingBooking(_ person: JSONValue, request: FinanceRequest, before: JSONValue?) -> JSONValue {
        var result = person
        if request.type == "status" {
            guard let before else { return person }
            result["status"] = before["status"]
            result["statusHistory"] = before["statusHistory"]
            return result
        }
        let id = id(request)
        result["payments"] = removing(id, from: person["payments"])
        result["standingOrders"] = removing(id, from: person["standingOrders"])
        return result
    }

    /// The expense list without the expense the approved [request] booked, nil when it is not there.
    static func removingExpense(_ expenses: [JSONValue], request: FinanceRequest) -> [JSONValue]? {
        let id = id(request)
        guard contains(.array(expenses), id: id) else { return nil }
        return removing(id, from: .array(expenses)).arrayValue
    }
}

/// One line of the finance timeline ("Verlauf"): payments, status changes and the fresh start, newest first.
struct TimelineEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case payment(amount: Double, note: String), status(String), freshStart }

    let id: String
    let date: String
    let kind: Kind
    /// Below the fresh start: the settled time before it, shown quieter.
    var settled = false

    var isFreshStart: Bool { kind == .freshStart }

    /// Like Android's `FeeLogic.timeline`: a fresh start is a marked point on the line; on its day it comes below that
    /// day's entries (they belong to the new account), and the entries below it are the settled time before it.
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
        // A history without entries stays empty (the screen says so), as on the web
        guard let reset = FeeRules.validDay(person.feeReset), !entries.isEmpty else { return entries.sorted { $0.date > $1.date } }
        entries.append(TimelineEntry(id: "fresh-start", date: reset, kind: .freshStart))
        var sorted = entries.sorted { $0.date != $1.date ? $0.date > $1.date : (!$0.isFreshStart && $1.isFreshStart) }
        if let at = sorted.firstIndex(where: \.isFreshStart) {
            for index in sorted.indices where index > at { sorted[index].settled = true }
        }
        return sorted
    }
}

/// What the app decides itself about the fees over time and the fresh start (CALDERA), like Android's `FeeLogic` and
/// the web app: everything calculated about the accounts comes from the server, these only decide what is shown.
enum FeeRules {
    /// How long the member card names a fresh start: a notice, not a fixture – the history keeps the day for good.
    static let newsDays = 60

    /// 'YYYY-MM-DD' that is a real day, else nil.
    static func validDay(_ value: String?) -> String? {
        guard let value, value.count == 10, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              Day.date(value) != nil else { return nil }
        return value
    }

    /// True while the fresh start on [resetDay] is news on [today]: from its day on for 60 days. A day still to come only
    /// shows on a device whose clock is behind – and counts as news.
    static func isNews(_ resetDay: String?, today: String) -> Bool {
        guard let reset = validDay(resetDay).flatMap(Day.date), let now = validDay(today).flatMap(Day.date) else { return false }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: reset, to: now).day ?? 0
        return days < newsDays
    }

    /// The dropped fees a payment dated [paymentDay] first makes up for before it becomes credit, or 0: a payment dated
    /// before the fresh start belongs to the time before it.
    static func droppedFeesBefore(_ person: Person?, paymentDay: String?) -> Double {
        guard let person, let reset = validDay(person.feeReset), let day = validDay(paymentDay), day < reset else { return 0 }
        return max(0, person.feeWrittenOff)
    }

    enum ResetOutcome: Equatable { case carriedOver, dropped, even }

    /// What happened to a member's fee account on its fresh start.
    static func resetOutcome(_ person: Person) -> ResetOutcome {
        if person.feeCarriedOver > 0 { return .carriedOver }
        if person.feeWrittenOff > 0 { return .dropped }
        return .even
    }
}
