import Foundation

// The books as API v2 hands them out (CALDERA, docs/API_V2.md in the agora repository): record ids, money in whole
// cents, days as 'YYYY-MM-DD', moments in ISO 8601 (UTC). Only the fields the app reads; v2 only grows, so anything else
// is ignored. Amounts are nil where no whole number of cents can hold them. Like Android's V2Models.kt.

/// Whole cents of a JSON number, nil for anything else.
private func centsValue(_ value: JSONValue?) -> Int64? {
    guard case .number(let number)? = value, number.isFinite, abs(number) < 1e15 else { return nil }
    return Int64(number.rounded())
}

/// Euros of whole [cents]: 0 for an amount nobody can read (as the old API's statistics count it).
func euros(_ cents: Int64?) -> Double { Double(cents ?? 0) / 100 }

/// Whole cents of [amount] in euros (rounded to the cent, as the server reads an amount).
func cents(_ amount: Double) -> Int64 { Int64((amount * 100).rounded()) }

/// The receipts as the app keeps them in one field: the web app's list as JSON text; none: nil.
func receiptField(_ names: [String]) -> String? {
    guard !names.isEmpty, let data = try? JSONEncoder().encode(names) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

/// One page of a list of API v2: its items in the list's fixed order, where the next page starts (nil on the last one)
/// and, for donations and expenses, the version of the whole list.
struct V2Page<Item: Decodable>: Decodable {
    var items: [Item] = []
    var nextCursor: String?
    var listVersion: String?

    init(items: [Item] = [], nextCursor: String? = nil, listVersion: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.listVersion = listVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // Lossy: one item the app cannot read does not lose the page
        items = (c.raw("items")?.arrayValue ?? []).compactMap { try? JSONDecoder().decode(Item.self, from: JSONEncoder().encode($0)) }
        nextCursor = c.optionalString("nextCursor").flatMap { $0.isEmpty ? nil : $0 }
        listVersion = c.optionalString("listVersion")
    }
}

/// What `GET /api/v2` names: the resources the server's v2 offers.
struct V2Index: Decodable {
    var resources: [String] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        resources = c.strings("resources")
    }
}

struct V2Payment: Decodable, Sendable {
    var id = ""
    var memberId = ""
    var amountCents: Int64?
    var date = ""
    var description = ""
    var receipts: [String] = []
    /// `manual`, `request` or `standingOrder`.
    var source = "manual"
    var memberVersion: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        memberId = c.string("memberId")
        amountCents = centsValue(c.raw("amountCents"))
        date = c.string("date")
        description = c.string("description")
        receipts = c.strings("receipts")
        source = c.string("source", "manual")
        memberVersion = c.optionalString("memberVersion")
    }
}

struct V2StatusPeriod: Decodable, Sendable {
    var status = ""
    var startDate = ""
    var endDate: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        status = c.string("status")
        startDate = c.string("startDate")
        endDate = c.optionalString("endDate").flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A standing order; [lastBookedOn]: the day of the month it booked last.
struct V2StandingOrder: Decodable, Sendable {
    var id = ""
    var memberId = ""
    var amountCents: Int64?
    var startDate = ""
    var endDate: String?
    var note = ""
    var lastBookedOn: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        memberId = c.string("memberId")
        amountCents = centsValue(c.raw("amountCents"))
        startDate = c.string("startDate")
        endDate = c.optionalString("endDate").flatMap { $0.isEmpty ? nil : $0 }
        note = c.string("note")
        lastBookedOn = c.optionalString("lastBookedOn")
    }
}

/// A member of the books (`GET /api/v2/members`, one of them with its rows: `/members/:id`): its record [id], the [key]
/// the old API knows it by, its [version] (a change of its books names it) and the fee account as the server works it
/// out. [feeState]: `overdue`, `standingOrder` or `ok` – anything else counts as in order.
struct V2Member: Decodable, Sendable {
    var id = ""
    var key = ""
    var userId: String?
    var name = ""
    var status = ""
    var memberSince = ""
    var originalMemberSince = ""
    var pays = true
    var isDeleted = false
    var totalPaidCents: Int64?
    var balanceCents: Int64?
    var overdueCents: Int64?
    var monthlyFeeCents: Int64?
    var paidUntil: String?
    var isOverdue = false
    var currentStatus: String?
    var feeState: String?
    var isDueSoon = false
    var hasActiveStandingOrder = false
    var freshStartDay: String?
    var carriedOverCents: Int64?
    var writtenOffCents: Int64?
    var version = ""
    // Only one member with its rows
    var payments: [V2Payment] = []
    var statusPeriods: [V2StatusPeriod] = []
    var standingOrders: [V2StandingOrder] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        key = c.string("key")
        userId = c.optionalString("userId").flatMap { $0.isEmpty ? nil : $0 }
        name = c.string("name")
        status = c.string("status")
        memberSince = c.string("memberSince")
        originalMemberSince = c.string("originalMemberSince")
        pays = c.bool("pays", true)
        isDeleted = c.bool("isDeleted")
        totalPaidCents = centsValue(c.raw("totalPaidCents"))
        balanceCents = centsValue(c.raw("balanceCents"))
        overdueCents = centsValue(c.raw("overdueCents"))
        monthlyFeeCents = centsValue(c.raw("monthlyFeeCents"))
        paidUntil = c.optionalString("paidUntil")
        isOverdue = c.bool("isOverdue")
        currentStatus = c.optionalString("currentStatus")
        feeState = c.optionalString("feeState")
        isDueSoon = c.bool("isDueSoon")
        hasActiveStandingOrder = c.bool("hasActiveStandingOrder")
        if let fresh = c.raw("freshStart")?.objectValue {
            freshStartDay = fresh["day"]?.text.flatMap { $0.isEmpty ? nil : $0 }
            carriedOverCents = centsValue(fresh["carriedOverCents"])
            writtenOffCents = centsValue(fresh["writtenOffCents"])
        }
        version = c.string("version")
        payments = c.models("payments")
        statusPeriods = c.models("statusPeriods")
        standingOrders = c.models("standingOrders")
    }

    /// The text the old API's fee account says (`_statusMeta.text`, a fixed protocol value).
    private var feeStateText: String {
        switch feeState {
        case "overdue": return "Zahlung überfällig"
        case "standingOrder": return "Dauerauftrag läuft"
        default: return "Alles in Ordnung"
        }
    }

    /// The member as the screens show a member record: the fee account as the server worked it out and – for one read
    /// with its rows – its payments, standing orders and status history. `Person.id` stays the key the old API knows
    /// the member by; `memberId` and `version` are what a change of its books through v2 names.
    func toPerson() -> Person {
        var person = Person()
        person.id = key.isEmpty ? id : key
        person.uid = userId ?? ""
        person.name = name
        person.status = status
        person.memberSince = memberSince
        person.originalMemberSince = originalMemberSince
        person.pays = pays
        person.totalPaid = euros(totalPaidCents)
        person.payments = payments.map { payment in
            var entry = Payment()
            entry.id = payment.id
            entry.amount = euros(payment.amountCents)
            entry.date = payment.date
            entry.description = payment.description
            entry.isAuto = payment.source == "standingOrder"
            return entry
        }
        person.standingOrders = standingOrders.map { order in
            var entry = StandingOrder()
            entry.id = order.id
            entry.amount = euros(order.amountCents)
            entry.startDate = order.startDate
            entry.endDate = order.endDate
            entry.note = order.note
            entry.lastAutoPayment = order.lastBookedOn
            return entry
        }
        person.statusHistory = statusPeriods.sorted { $0.startDate < $1.startDate }.map { period in
            var entry = StatusHistoryEntry()
            entry.status = period.status
            entry.startDate = period.startDate
            entry.endDate = period.endDate
            return entry
        }
        person.isDeleted = isDeleted
        person.paidUntil = paidUntil
        var meta = StatusMeta()
        meta.text = feeStateText
        meta.isOverdue = feeState == "overdue" || isOverdue
        meta.isSoonDue = isDueSoon
        meta.isActiveStandingOrder = hasActiveStandingOrder
        person.statusMeta = meta
        person.overdueAmount = euros(overdueCents)
        person.currentStatus = currentStatus
        person.currentBalance = euros(balanceCents)
        person.feeReset = freshStartDay
        person.feeCarriedOver = euros(carriedOverCents)
        person.feeWrittenOff = euros(writtenOffCents)
        person.monthlyFee = monthlyFeeCents.map { euros($0) }
        person.memberId = id
        person.version = version
        return person
    }
}

/// A booking of the history (`GET /api/v2/finance/ledger`): [kind] `memberPayment`, `donation` or `expense`; [who] the
/// member, donor or issuer.
struct V2LedgerEntry: Decodable, Sendable {
    var kind = ""
    var id = ""
    var amountCents: Int64?
    var date = ""
    var who = ""
    var memberId: String?
    var description = ""
    var receipts: [String] = []
    var source: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        kind = c.string("kind")
        id = c.string("id")
        amountCents = centsValue(c.raw("amountCents"))
        date = c.string("date")
        who = c.string("who")
        memberId = c.optionalString("memberId")
        description = c.string("description")
        receipts = c.strings("receipts")
        source = c.optionalString("source")
    }

    /// Approved expense requests of older versions kept the requester only as "(Von: Name)" in the description.
    private static let fromInDescription = try? NSRegularExpression(pattern: #"^(.*?)\s*\(Von: ([^)]+)\)\s*$"#, options: [.dotMatchesLineSeparators])

    /// The booking as the history shows it; [members]: the members by record id. Nil for a kind of booking the app does
    /// not know (v2 may grow one): whether it is income or an expense cannot be told.
    func toTransaction(members: [String: V2Member]) -> Transaction? {
        let type: String
        switch kind {
        case "memberPayment": type = "pay"
        case "donation": type = "don"
        case "expense": type = "exp"
        default: return nil
        }
        let member = memberId.flatMap { members[$0] }
        var transaction = Transaction()
        transaction.id = id
        transaction.type = type
        transaction.who = who
        transaction.date = date
        transaction.amount = euros(amountCents)
        transaction.description = description
        if type == "exp", who.trimmingCharacters(in: .whitespaces).isEmpty, let regex = Self.fromInDescription,
           let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
           let text = Range(match.range(at: 1), in: description), let name = Range(match.range(at: 2), in: description) {
            transaction.description = description[text].trimmingCharacters(in: .whitespaces)
            transaction.who = description[name].trimmingCharacters(in: .whitespaces)
        }
        transaction.personUid = member?.userId
        transaction.personId = member?.key ?? ""
        transaction.receipt = receiptField(receipts)
        transaction.isAuto = source == "standingOrder"
        return transaction
    }
}

/// A request (`GET /api/v2/requests`). [memberId]: the member it is about (nil for someone without a record of the
/// books); [details]: what was asked, as the app sent it.
struct V2Request: Decodable, Sendable {
    var id = ""
    var type = ""
    var status = "pending"
    var userId = ""
    var memberId: String?
    var memberName = ""
    var details: [String: JSONValue] = [:]
    var createdAt: String?
    var rejectionReason: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        type = c.string("type")
        status = c.string("status", "pending")
        userId = c.string("userId")
        memberId = c.optionalString("memberId").flatMap { $0.isEmpty ? nil : $0 }
        memberName = c.string("memberName")
        details = c.object("details")
        createdAt = c.optionalString("createdAt")
        rejectionReason = c.optionalString("rejectionReason")
    }

    /// The request as the app shows it; [members]: the members by record id (for the key of the member it is about).
    func toFinanceRequest(members: [String: V2Member]) -> FinanceRequest {
        let member = memberId.flatMap { members[$0] }
        var request = FinanceRequest()
        request.id = id
        request.type = type
        request.userId = userId
        request.personId = member?.key ?? memberId ?? ""
        request.personName = memberName.trimmingCharacters(in: .whitespaces).isEmpty ? (member?.name ?? "") : memberName
        request.data = details
        request.status = status
        request.rejectionReason = rejectionReason
        request.timestamp = createdAt.flatMap(Formats.timestamp).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        request.v2 = true
        request.memberId = memberId
        return request
    }
}

/// The money as the statistics count it (`GET /api/v2/finance/summary`): booked up to today.
struct V2Summary: Decodable, Sendable {
    var memberPayments: Int64 = 0
    var donations: Int64 = 0
    var expenses: Int64 = 0
    var balance: Int64 = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let totals = c.raw("totalsCents")?.objectValue ?? [:]
        memberPayments = centsValue(totals["memberPayments"]) ?? 0
        donations = centsValue(totals["donations"]) ?? 0
        expenses = centsValue(totals["expenses"]) ?? 0
        balance = centsValue(totals["balance"]) ?? 0
    }

    func toStats() -> FinanceStats {
        var stats = FinanceStats()
        stats.totalBalance = euros(balance)
        stats.totalIncome = euros(memberPayments + donations)
        stats.totalExpenses = euros(expenses)
        return stats
    }
}

/// What the server names an uploaded receipt (`POST /api/v2/receipts`).
struct V2Upload: Decodable, Sendable {
    var name = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.string("name")
    }
}

/// Where the next page of the treasury's history starts: a page number of the old API, or v2's cursor.
enum HistoryCursor: Hashable, Sendable {
    case page(Int)
    case v2(String)
}
