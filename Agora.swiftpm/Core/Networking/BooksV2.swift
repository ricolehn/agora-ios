import Foundation

/// The books through API v2 (CALDERA), like Android's `BooksV2`: members with their fee accounts, payments, standing
/// orders, status changes, donations, expenses, receipts, requests, the history and the money summary.
///
/// Every change names the version of the data it is based on – a payment, a standing order or a status change its
/// member's version, a donation or an expense the version of its list – and is refused (409) when that data changed
/// meanwhile. Then the version is read again and the change repeated: a new entry overwrites nothing someone else did.
final class BooksV2: @unchecked Sendable {
    /// A change refused for a newer version is read again and repeated this often at most.
    static let attempts = 3
    /// Entries of the history shown at a time.
    static let historyPage = 50
    /// The longest search v2 takes.
    private static let searchLimit = 200

    private let v2: ApiV2
    private let lock = NSLock()
    /// The members as last read, by record id (the names of the history, the ids for a booking).
    private var directory: [String: V2Member]?

    init(v2: ApiV2) { self.v2 = v2 }

    // MARK: Members

    /// Every member the person may see, by record id, with their fee accounts – those with finance rights all of them,
    /// deleted ones included (their payments stay in the books), everyone else their own. [fresh] false: the members as
    /// last read, if any.
    func members(fresh: Bool = true) async throws -> [String: V2Member] {
        if !fresh, let known = lock.withLock({ directory }) { return known }
        let list = try await v2.all("/members", of: V2Member.self, query: ["includeDeleted": "1"]).items
        let byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lock.withLock { directory = byId }
        return byId
    }

    /// The member the old API knows by [key] (the app's person records keep it as their id), or nil.
    func memberByKey(_ key: String) async throws -> V2Member? {
        if let known = try await members(fresh: false).values.first(where: { $0.key == key }) { return known }
        return try await members().values.first { $0.key == key }
    }

    /// One member with its payments, standing orders and status periods.
    func member(_ id: String) async throws -> V2Member { try await v2.call(.get, "/members/\(ApiV2.segment(id))") }

    /// The version the books of member [memberId] have now.
    func memberVersion(_ memberId: String) async throws -> String { try await member(memberId).version }

    /// A change of member [memberId]'s books that adds or sets something ([change] gets the version): a newer version is
    /// read again and the change made on it.
    private func onMember<T>(_ memberId: String, version: String?, _ change: (String) async throws -> T) async throws -> T {
        var current: String
        if let version, !version.isEmpty { current = version } else { current = try await memberVersion(memberId) }
        for attempt in 0..<Self.attempts {
            do {
                return try await change(current)
            } catch let error as APIError where error.status == 409 && attempt < Self.attempts - 1 {
                current = try await memberVersion(memberId)
            }
        }
        throw APIError(status: 409, message: "Conflict", code: "conflict")
    }

    // MARK: Payments, standing orders, status changes

    /// Books a payment for member [memberId]. With [requestId] it is the booking of that request: booked once, however
    /// often it is sent.
    func addPayment(memberId: String, version: String?, amountCents: Int64, date: String, description: String,
                    requestId: String? = nil) async throws {
        try await onMember(memberId, version: version) { current in
            var body: JSONValue = [
                "memberId": .string(memberId), "memberVersion": .string(current), "amountCents": .number(Double(amountCents)),
                "date": .string(date), "description": .string(description)
            ]
            if let requestId { body["requestId"] = .string(requestId) }
            try await v2.perform(.post, "/payments", body: body)
        }
    }

    /// A standing order for member [memberId]: what it owes from its start up to today is booked at once.
    func addStandingOrder(memberId: String, version: String?, amountCents: Int64, startDate: String, note: String) async throws {
        try await onMember(memberId, version: version) { current in
            try await v2.perform(.post, "/standing-orders", body: [
                "memberId": .string(memberId), "memberVersion": .string(current), "amountCents": .number(Double(amountCents)),
                "startDate": .string(startDate), "note": .string(note)
            ])
        }
    }

    /// Ends the standing order [orderId] on [endDate] (also a day that has passed: what it booked after it is taken back).
    func endStandingOrder(memberId: String, version: String?, orderId: String, endDate: String) async throws {
        try await onMember(memberId, version: version) { current in
            try await v2.perform(.patch, "/standing-orders/\(ApiV2.segment(orderId))",
                                 body: ["memberVersion": .string(current), "endDate": .string(endDate)])
        }
    }

    /// Removes the standing order [orderId]; the payments it booked stay.
    func deleteStandingOrder(memberId: String, version: String?, orderId: String) async throws {
        try await onMember(memberId, version: version) { current in
            try await v2.perform(.delete, "/standing-orders/\(ApiV2.segment(orderId))", query: ["memberVersion": current])
        }
    }

    /// Member [memberId]'s income status from [date] on (the server rewrites the history as the web app does).
    func changeStatus(memberId: String, version: String?, status: String, date: String) async throws {
        try await onMember(memberId, version: version) { current in
            try await v2.perform(.post, "/status-changes", body: [
                "memberId": .string(memberId), "memberVersion": .string(current), "status": .string(status), "date": .string(date)
            ])
        }
    }

    // MARK: Donations and expenses: lists with a version

    /// The version a list ("donations", "expenses") has now (its first page names it).
    private func listVersion(_ list: String) async throws -> String {
        try await v2.page("/\(list)", of: JSONValue.self, limit: 1).listVersion ?? ""
    }

    /// A new entry of [list]: it overwrites nothing – a newer list is read again and it goes on.
    private func addToList(_ list: String, _ body: (String) -> JSONValue) async throws {
        var version = try await listVersion(list)
        for attempt in 0..<Self.attempts {
            do {
                try await v2.perform(.post, "/\(list)", body: body(version))
                return
            } catch let error as APIError where error.status == 409 && attempt < Self.attempts - 1 {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 50_000_000...400_000_000))
                version = try await listVersion(list)
            }
        }
    }

    func addDonation(amountCents: Int64, date: String, donorName: String, description: String) async throws {
        try await addToList("donations") { version in
            ["listVersion": .string(version), "amountCents": .number(Double(amountCents)), "date": .string(date),
             "donorName": .string(donorName), "description": .string(description)]
        }
    }

    /// [receipts]: the names of its receipts (`uploadReceipt`).
    func addExpense(amountCents: Int64, date: String, issuer: String, description: String, receipts: [String]) async throws {
        try await addToList("expenses") { version in
            ["listVersion": .string(version), "amountCents": .number(Double(amountCents)), "date": .string(date),
             "issuer": .string(issuer), "description": .string(description), "receipts": .array(receipts.map(JSONValue.string))]
        }
    }

    // MARK: Receipts

    /// Uploads a receipt (a picture or a PDF); answers the name an entry or a request names it by.
    func uploadReceipt(fileName: String, mimeType: String, data: Data) async throws -> String {
        let upload: V2Upload = try await v2.upload("/receipts", file: .init(field: "receipt", fileName: fileName, mimeType: mimeType, data: data))
        return upload.name
    }

    // MARK: Requests

    /// The requests the person may see, as the app shows them, newest first.
    func requests() async throws -> [FinanceRequest] {
        async let list = v2.all("/requests", of: V2Request.self).items
        async let directory = members(fresh: false)
        let byId = (try? await directory) ?? [:]
        return try await list.map { $0.toFinanceRequest(members: byId) }.sorted { $0.timestamp > $1.timestamp }
    }

    /// Asks the treasury: [type] with what is asked ([details]), about the asking member's own record [memberId] (nil: the
    /// one the server finds for the account); the treasurers are told, as they chose. A member's record can bear another
    /// key than the account (made by the treasury, linked later): where it is known, it is named.
    func ask(type: String, details: [String: JSONValue], memberId: String?) async throws {
        var body: JSONValue = ["type": .string(type), "details": .object(details), "notify": true]
        if let memberId { body["memberId"] = .string(memberId) }
        try await v2.perform(.post, "/requests", body: body)
    }

    /// Decides request [id] once ([status] approved or rejected): 409 when it was decided already. With [book] an
    /// approval books what the request asks for in the same step – once, as the web app books it.
    func decide(id: String, status: String, rejectionReason: String? = nil, book: Bool = false) async throws {
        var body: JSONValue = ["status": .string(status)]
        if let rejectionReason { body["rejectionReason"] = .string(rejectionReason) }
        if book { body["book"] = true }
        try await v2.perform(.post, "/requests/\(ApiV2.segment(id))/decision", body: body)
    }

    // MARK: The money and the history

    func summary() async throws -> FinanceStats {
        let summary: V2Summary = try await v2.call(.get, "/finance/summary")
        return summary.toStats()
    }

    /// One page of the history, newest first, after [cursor] (nil: the first); with [search] only what the server finds.
    func history(search: String, cursor: String?) async throws -> (items: [Transaction], next: String?) {
        let byId = try await members(fresh: cursor != nil ? false : true)
        let text = String(search.trimmingCharacters(in: .whitespaces).prefix(Self.searchLimit))
        let page = try await v2.page("/finance/ledger", of: V2LedgerEntry.self, query: text.isEmpty ? [:] : ["q": text],
                                     cursor: cursor, limit: Self.historyPage)
        return (page.items.compactMap { $0.toTransaction(members: byId) }, page.nextCursor)
    }

    /// Every booking, newest first (the financial report).
    func allBookings() async throws -> [Transaction] {
        let byId = try await members()
        return try await v2.all("/finance/ledger", of: V2LedgerEntry.self).items.compactMap { $0.toTransaction(members: byId) }
    }
}
