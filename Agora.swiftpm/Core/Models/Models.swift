import Foundation

// Decoding is tolerant everywhere (see LenientDecoding.swift); encoding is synthesized and only used for the
// on-device cache, which is read back by the same decoders.

// MARK: - Auth & user

struct StatusResponse: Codable, Sendable {
    var setupMode = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        setupMode = c.bool("setupMode")
    }
}

struct AuthResponse: Decodable, Sendable {
    var token: String?
    var user: User?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        token = c.optionalString("token")
        user = c.model("user")
    }
}

struct NotificationSettings: Codable, Hashable, Sendable {
    var duties = true
    var events = true
    var messages = true
    var finances = true

    init(duties: Bool = true, events: Bool = true, messages: Bool = true, finances: Bool = true) {
        self.duties = duties
        self.events = events
        self.messages = messages
        self.finances = finances
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        duties = c.bool("duties", true)
        events = c.bool("events", true)
        messages = c.bool("messages", true)
        finances = c.bool("finances", true)
    }

    var any: Bool { duties || events || messages || finances }
}

struct User: Codable, Hashable, Sendable {
    var uid = ""
    var id = ""
    var email = ""
    var firstName = ""
    var lastName = ""
    var name = ""
    var admin = false
    var owner = false
    var superAdmin = false
    var pays = true
    var groups: [String] = []
    var permissions: [String] = []
    var emailNotifications = true
    var notificationSettings: NotificationSettings?
    var isClaimed = true
    var calendarToken = ""
    var canManageFinances = false
    var canViewFinances = false
    var canManageRegistrationCode = false
    var canAccessAi = false
    var canParticipateMentoring = true
    var canManageMentoring = false
    var canManageEvents = false
    var mentorStatus: String?
    var isApprovedMentor = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        uid = c.string("uid")
        id = c.string("id")
        email = c.string("email")
        firstName = c.string("firstName")
        lastName = c.string("lastName")
        name = c.string("name")
        admin = c.bool("admin")
        owner = c.bool("owner")
        superAdmin = c.bool("superAdmin")
        pays = c.bool("pays", true)
        groups = c.strings("groups")
        permissions = c.strings("permissions")
        emailNotifications = c.bool("emailNotifications", true)
        notificationSettings = c.model("notificationSettings")
        isClaimed = c.bool("isClaimed", true)
        calendarToken = c.string("calendarToken")
        canManageFinances = c.bool("canManageFinances")
        canViewFinances = c.bool("canViewFinances")
        canManageRegistrationCode = c.bool("canManageRegistrationCode")
        canAccessAi = c.bool("canAccessAi")
        canParticipateMentoring = c.bool("canParticipateMentoring", true)
        canManageMentoring = c.bool("canManageMentoring")
        canManageEvents = c.bool("canManageEvents")
        mentorStatus = c.optionalString("mentorStatus")
        isApprovedMentor = c.bool("isApprovedMentor") || mentorStatus == "approved"
    }

    var userId: String { uid.isEmpty ? id : uid }

    var fullName: String {
        if !name.isEmpty { return name }
        let joined = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? email : joined
    }

    var initials: String { Initials.of(fullName) }
    var isAdmin: Bool { admin || owner || superAdmin }
    var managesFinances: Bool { canManageFinances || permissions.contains("manage_finances") }
    var viewsFinances: Bool { managesFinances || canViewFinances || permissions.contains("view_finances") }
    var managesEvents: Bool { canManageEvents || permissions.contains("manage_events") }
    var managesMentoring: Bool { canManageMentoring || permissions.contains("manage_mentoring") }
    var managesRegistrationCode: Bool { canManageRegistrationCode || permissions.contains("manage_registration_code") }
    var accessesAi: Bool { canAccessAi || permissions.contains("access_ai") }

    var effectiveNotifications: NotificationSettings {
        notificationSettings ?? (emailNotifications ? NotificationSettings()
            : NotificationSettings(duties: false, events: false, messages: false, finances: false))
    }

    /// Ring around the own picture like the web app: managers gold-red, approved mentors purple, others cyan-green.
    var ring: AvatarRingKind {
        if managesMentoring { return .manager }
        if isApprovedMentor { return .mentor }
        return .standard
    }
}

enum AvatarRingKind: String, Codable, Sendable { case standard, mentor, manager }

struct MemberGroup: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var name = ""

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        name = c.string("name")
    }
}

enum Initials {
    static func of(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

// MARK: - Finances

/// Monthly fee per member status (EUR), from `settings`.
struct FeeSettings: Codable, Hashable, Sendable {
    var rates: [String: Double] = [:]

    init(rates: [String: Double] = [:]) { self.rates = rates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // The cache stores {rates: {...}}, the server answers the plain settings object
        if let nested = c.raw("rates")?.objectValue {
            rates = nested.compactMapValues(\.amount)
        } else {
            var result: [String: Double] = [:]
            for key in c.allKeys { if let amount = c.raw(key.stringValue)?.amount { result[key.stringValue] = amount } }
            rates = result
        }
    }

    func rate(for status: String?) -> Double { rates[status ?? ""] ?? 0 }
}

/// Member statuses; the first three have a monthly fee (settings), "pausiert" pays nothing.
enum MemberStatus: String, CaseIterable, Identifiable, Sendable {
    case vollverdiener, geringverdiener, keinverdiener, pausiert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vollverdiener: return "💼 Vollverdiener"
        case .geringverdiener: return "📉 Geringverdiener"
        case .keinverdiener: return "🎓 Keinverdiener"
        case .pausiert: return "⏸️ Pausiert"
        }
    }

    /// Statuses with a fee in the settings.
    static let paying: [MemberStatus] = [.vollverdiener, .geringverdiener, .keinverdiener]

    static func label(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "–" }
        return MemberStatus(rawValue: raw)?.label ?? raw
    }
}

struct Payment: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var amount = 0.0
    var date = ""
    var description = ""
    var isAuto = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        amount = c.double("amount")
        date = c.string("date")
        description = c.string("description")
        isAuto = c.bool("isAuto")
    }
}

struct StandingOrder: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var amount = 0.0
    var startDate = ""
    var endDate: String?
    var note = ""
    var lastAutoPayment: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        amount = c.double("amount")
        startDate = c.string("startDate")
        endDate = c.optionalString("endDate").flatMap { $0.isEmpty ? nil : $0 }
        note = c.string("note")
        lastAutoPayment = c.optionalString("lastAutoPayment")
    }

    /// Running on [today]: started and not ended before.
    func isActive(on today: String) -> Bool { startDate <= today && (endDate.map { $0 >= today } ?? true) }
}

struct StatusHistoryEntry: Codable, Hashable, Sendable {
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

/// Server-computed payment state of a person (`_statusMeta`).
struct StatusMeta: Codable, Hashable, Sendable {
    var text = ""
    var isOverdue = false
    var isSoonDue = false
    var isActiveStandingOrder = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        text = c.string("text")
        isOverdue = c.bool("isOverdue")
        isSoonDue = c.bool("isSoonDue")
        isActiveStandingOrder = c.bool("isActiveStandingOrder")
    }
}

struct Person: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var uid = ""
    var name = ""
    var status = ""
    var memberSince = ""
    var originalMemberSince = ""
    var pays = true
    var totalPaid = 0.0
    var payments: [Payment] = []
    var standingOrders: [StandingOrder] = []
    var statusHistory: [StatusHistoryEntry] = []
    var isDeleted = false
    var paidUntil: String?
    var statusMeta = StatusMeta()
    var overdueAmount = 0.0
    var currentStatus: String?
    var currentBalance = 0.0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        uid = c.string("uid")
        name = c.string("name")
        status = c.string("status")
        memberSince = c.string("memberSince")
        originalMemberSince = c.string("originalMemberSince")
        pays = c.bool("pays", true)
        totalPaid = c.double("totalPaid")
        payments = c.models("payments")
        standingOrders = c.models("standingOrders")
        statusHistory = c.models("statusHistory")
        isDeleted = c.bool("isDeleted")
        // Server fields carry a leading underscore; the on-device cache writes the plain names
        paidUntil = c.optionalString("_paidUntil") ?? c.optionalString("paidUntil")
        statusMeta = c.model("_statusMeta") ?? c.model("statusMeta") ?? StatusMeta()
        overdueAmount = c.raw("_overdueAmount") != nil ? c.double("_overdueAmount") : c.double("overdueAmount")
        currentStatus = c.optionalString("_currentStatus") ?? c.optionalString("currentStatus")
        currentBalance = c.raw("_currentBalance") != nil ? c.double("_currentBalance") : c.double("currentBalance")
    }

    var effectiveStatus: String { currentStatus ?? status }
    var sortedPayments: [Payment] { payments.sorted { $0.date > $1.date } }
}

struct FinanceRequest: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var type = ""
    var userId = ""
    var personId = ""
    var personName = ""
    var data: [String: JSONValue] = [:]
    var status = "pending"
    var rejectionReason: String?
    var timestamp: Int64 = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        type = c.string("type")
        userId = c.string("userId")
        personId = c.string("personId")
        personName = c.string("personName")
        data = c.object("data")
        status = c.string("status", "pending")
        rejectionReason = c.optionalString("rejectionReason")
        timestamp = c.int64("timestamp")
    }

    func field(_ key: String) -> String? { data[key]?.text }
    var amount: Double { data["amount"]?.amount ?? 0 }
    var isPending: Bool { status == "pending" }

    /// Receipt file names: a single name or a JSON list in a string.
    var receipts: [String] { Receipts.parse(data["receipt"]) }

    var typeLabel: String {
        switch type {
        case "payment": return "Zahlung"
        case "standing_order": return "Dauerauftrag"
        case "status": return "Statusänderung"
        case "expense": return "Auslage"
        default: return type
        }
    }
}

enum Receipts {
    static func parse(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        if let list = value.arrayValue { return list.compactMap(\.text).filter { !$0.isEmpty } }
        guard let text = value.text, !text.isEmpty else { return [] }
        if text.hasPrefix("["), let data = text.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) {
            return list.filter { !$0.isEmpty }
        }
        return [text]
    }
}

struct Transaction: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var type = ""
    var who = ""
    var date = ""
    var amount = 0.0
    var description = ""
    var personUid: String?
    var personId = ""
    var receipt: String?
    var isAuto = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        type = c.string("type")
        who = c.string("who")
        date = c.string("date")
        amount = c.double("amount")
        description = c.string("description")
        personUid = c.optionalString("personUid")
        personId = c.string("personId")
        receipt = c.optionalString("receipt")
        isAuto = c.bool("isAuto")
    }

    var isIncome: Bool { type != "exp" }
    var receipts: [String] { Receipts.parse(receipt.map(JSONValue.string)) }
}

struct TransactionPage: Decodable, Sendable {
    var items: [Transaction] = []
    var totalItems = 0
    var page = 1
    var perPage = 150
    var totalPages = 1

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        items = c.models("items")
        totalItems = c.int("totalItems")
        page = c.int("page", 1)
        perPage = c.int("perPage", 150)
        totalPages = c.int("totalPages", 1)
    }
}

struct FinanceStats: Decodable, Sendable {
    var totalBalance = 0.0
    var totalIncome = 0.0
    var totalExpenses = 0.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        totalBalance = c.double("totalBalance")
        totalIncome = c.double("totalIncome")
        totalExpenses = c.double("totalExpenses")
    }
}

struct UploadResponse: Decodable, Sendable {
    var filename = ""
    var url = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        filename = c.string("filename")
        url = c.string("url")
    }
}

// MARK: - Events

struct Registration: Codable, Hashable, Sendable {
    var id = ""
    var status = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        status = c.string("status")
    }
}

struct Duty: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var event = ""
    var section = ""
    var roleName = ""
    var assignedGroup = ""
    var assignedGroupName = ""
    var assignedUser = ""
    var assignedUserName = ""
    var requestedUser = ""
    var requestedUserName = ""
    var requestedBy = ""
    var requestedByName = ""
    var notes = ""
    var status = "open"
    var canEditNotes = false
    var canManageDuty = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        event = c.string("event")
        section = c.string("section")
        roleName = c.string("roleName")
        assignedGroup = c.string("assignedGroup")
        assignedGroupName = c.string("assignedGroupName")
        assignedUser = c.string("assignedUser")
        assignedUserName = c.string("assignedUserName")
        requestedUser = c.string("requestedUser")
        requestedUserName = c.string("requestedUserName")
        requestedBy = c.string("requestedBy")
        requestedByName = c.string("requestedByName")
        notes = c.string("notes")
        status = c.string("status", "open")
        canEditNotes = c.bool("canEditNotes")
        canManageDuty = c.bool("canManageDuty")
    }

    // Slot states from the server: open, requested (asked a person), confirmed (person agreed),
    // assigned (a group holds it), declined (the asked person said no; the slot is free again)
    var isOpen: Bool { status == "open" || status == "declined" }
    var isRequested: Bool { status == "requested" }
    var isConfirmed: Bool { status == "confirmed" }
    var isDeclined: Bool { status == "declined" }
    var isGroup: Bool { !assignedGroup.isEmpty || !assignedGroupName.isEmpty }
    /// Counts as filled in the roster summary.
    var isFilled: Bool { isConfirmed || (status == "assigned" && isGroup) }
    /// Someone (person, request or group) is entered on this slot.
    var hasAssignee: Bool { !assignedUser.isEmpty || !requestedUser.isEmpty || isGroup }

    var groupName: String { assignedGroupName.isEmpty ? assignedGroup : assignedGroupName }
    var personName: String { assignedUserName.isEmpty ? requestedUserName : assignedUserName }
    var role: String { roleName.trimmingCharacters(in: .whitespaces).isEmpty ? "Aufgabe" : roleName.trimmingCharacters(in: .whitespaces) }
}

struct AgoraEvent: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var title = ""
    var date = ""
    var endDate = ""
    var startTime = ""
    var endTime = ""
    var location = ""
    var description = ""
    var eventType = "event"
    var isPinned = false
    var isRecurring = false
    var recurringRule = ""
    var status = ""
    var requiresRegistration = false
    var minParticipants = 0
    var maxParticipants = 0
    var targetGroups: [String] = []
    var createdBy = ""
    var createdByName = ""
    var imageUrl = ""
    var duties: [Duty] = []
    var registeredCount = 0
    var waitlistCount = 0
    var myRegistration: Registration?
    var isFull = false
    var canEdit = false
    var canAccessDutyPlan = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        title = c.string("title")
        date = c.string("date")
        endDate = c.string("endDate")
        startTime = c.string("startTime")
        endTime = c.string("endTime")
        location = c.string("location")
        description = c.string("description")
        eventType = c.string("eventType", "event")
        isPinned = c.bool("isPinned")
        isRecurring = c.bool("isRecurring")
        recurringRule = c.string("recurringRule")
        status = c.string("status")
        requiresRegistration = c.bool("requiresRegistration")
        minParticipants = c.int("minParticipants")
        maxParticipants = c.int("maxParticipants")
        targetGroups = c.strings("targetGroups")
        createdBy = c.string("createdBy")
        createdByName = c.string("createdByName")
        imageUrl = c.string("imageUrl")
        duties = c.models("duties")
        registeredCount = c.int("registeredCount")
        waitlistCount = c.int("waitlistCount")
        myRegistration = c.model("myRegistration")
        isFull = c.bool("isFull")
        canEdit = c.bool("canEdit")
        canAccessDutyPlan = c.bool("canAccessDutyPlan")
    }

    var isTermin: Bool { eventType == "termin" }
    var lastDay: String { endDate.isEmpty ? date : endDate }
    var isMultiDay: Bool { !endDate.isEmpty && endDate != date }
    var isRegistered: Bool { myRegistration?.status == "registered" }
    var isWaitlisted: Bool { myRegistration?.status == "waitlist" }
    func isPast(today: String = Day.today()) -> Bool { !lastDay.isEmpty && lastDay < today }
    func isOngoing(today: String = Day.today()) -> Bool { date <= today && lastDay >= today }

    /// Duty the user holds personally (agreed).
    func myConfirmedDuty(_ user: User) -> Duty? { duties.first { $0.assignedUser == user.userId && $0.isConfirmed } }
    /// Duty the user holds through one of their groups.
    func myGroupDuty(_ user: User) -> Duty? { duties.first { user.groups.contains($0.assignedGroup) && $0.status == "assigned" } }
    /// Duty the user was asked for and has not answered yet.
    func myOpenRequest(_ user: User) -> Duty? { duties.first { $0.requestedUser == user.userId && $0.isRequested } }
    func hasMyDuty(_ user: User) -> Bool { myConfirmedDuty(user) != nil || myGroupDuty(user) != nil || myOpenRequest(user) != nil }
    var openDutySlots: Int { duties.filter(\.isOpen).count }
    var isCancelled: Bool { status == "cancelled" }
}

struct DutyRequest: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var eventId = ""
    var eventTitle = ""
    var eventDate = ""
    var eventStartTime = ""
    var eventEndTime = ""
    var eventLocation = ""
    var section = ""
    var roleName = ""
    var requestedBy = ""
    var requestedByName = ""
    var notes = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        eventId = c.string("eventId")
        eventTitle = c.string("eventTitle")
        eventDate = c.string("eventDate")
        eventStartTime = c.string("eventStartTime")
        eventEndTime = c.string("eventEndTime")
        eventLocation = c.string("eventLocation")
        section = c.string("section")
        roleName = c.string("roleName")
        requestedBy = c.string("requestedBy")
        requestedByName = c.string("requestedByName")
        notes = c.string("notes")
    }
}

struct Attendee: Decodable, Hashable, Identifiable, Sendable {
    var id = ""
    var userId = ""
    var name = ""
    var status = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        userId = c.string("userId")
        name = c.string("name")
        status = c.string("status")
    }
}

struct Attendees: Decodable, Sendable {
    var registered: [Attendee] = []
    var waitlist: [Attendee] = []
    var maxParticipants = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        registered = c.models("registered")
        waitlist = c.models("waitlist")
        maxParticipants = c.int("maxParticipants")
    }
}

struct Candidate: Decodable, Hashable, Identifiable, Sendable {
    var id = ""
    var name = ""
    var email = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        name = c.string("name")
        email = c.string("email")
    }
}

struct Candidates: Decodable, Sendable {
    var candidates: [Candidate] = []
    var groups: [MemberGroup] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        candidates = c.models("candidates")
        groups = c.models("groups")
    }
}

struct EventSettings: Codable, Hashable, Sendable {
    var allowMemberCreation = true
    var defaultDuties: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        allowMemberCreation = c.bool("allowMemberCreation", true)
        defaultDuties = c.strings("defaultDuties")
    }
}

struct CalendarFeed: Decodable, Sendable {
    var feedUrl = ""
    var webcalUrl = ""
    var calendarToken = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        feedUrl = c.string("feedUrl")
        webcalUrl = c.string("webcalUrl")
        calendarToken = c.string("calendarToken")
    }
}

// MARK: - Mentoring

struct Mentor: Decodable, Hashable, Identifiable, Sendable {
    var id = ""
    var user = ""
    var name = ""
    var mentorName = ""
    var status = ""
    var bio = ""
    var maxMentees = 0
    var activeMentees = 0
    var isFull = false
    var isAccepting = true
    var userEmail: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        user = c.string("user")
        name = c.string("name")
        mentorName = c.string("mentorName")
        status = c.string("status")
        bio = c.string("bio")
        maxMentees = c.int("maxMentees", c.int("max_mentees"))
        activeMentees = c.int("activeMentees")
        isFull = c.bool("isFull")
        isAccepting = c.bool("isAccepting", true)
        userEmail = c.optionalString("userEmail")
    }

    var displayName: String { mentorName.isEmpty ? name : mentorName }
}

struct MentorProfile: Codable, Hashable, Sendable {
    var id = ""
    var status = ""
    var bio = ""
    var maxMentees = 3
    var isAccepting = true

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        status = c.string("status")
        bio = c.string("bio")
        maxMentees = c.int("maxMentees", c.int("max_mentees", 3))
        isAccepting = c.bool("isAccepting", true)
    }
}

struct MyMentorProfile: Codable, Hashable, Sendable {
    var exists = false
    var mentor: MentorProfile?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        exists = c.bool("exists")
        mentor = c.model("mentor")
    }

    var isApproved: Bool { mentor?.status == "approved" }
    var isPending: Bool { mentor?.status == "pending" }
}

struct LastMessage: Codable, Hashable, Sendable {
    var text = ""
    var created = ""
    var senderRole = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        text = c.string("text")
        created = c.string("created")
        senderRole = c.string("senderRole")
    }
}

struct MentoringThread: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var mentor = ""
    var mentee: String?
    var status = "active"
    var created = ""
    var updated = ""
    var unreadCount = 0
    var lastMessage: LastMessage?
    var myRole = "mentee"
    var mentorName = ""
    var menteeAlias = ""
    var title = ""
    /// Closed by a block; only the one who blocked (`blockedByMe`) can reopen it.
    var blocked = false
    var blockedByMe = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        mentor = c.string("mentor")
        mentee = c.optionalString("mentee")
        status = c.string("status", "active")
        created = c.string("created")
        updated = c.string("updated")
        unreadCount = c.int("unreadCount", c.int("unread_count"))
        lastMessage = c.model("lastMessage")
        myRole = c.string("myRole", "mentee")
        mentorName = c.string("mentorName")
        menteeAlias = c.string("menteeAlias")
        title = c.string("title")
        blocked = c.bool("blocked")
        blockedByMe = c.bool("blockedByMe")
    }

    var isClosed: Bool { status == "closed" }
    var iAmMentor: Bool { myRole == "mentor" }
    var partnerName: String { !title.isEmpty ? title : (iAmMentor ? menteeAlias : mentorName) }
    /// Mentees see their mentor's picture; mentors only know the anonymous alias.
    var partnerPictureUserId: String? { iAmMentor ? nil : mentor }
    var lastActivity: String { lastMessage?.created.isEmpty == false ? lastMessage!.created : (updated.isEmpty ? created : updated) }
}

struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var thread = ""
    var senderRole = ""
    var sender = ""
    var text = ""
    var read = false
    var created = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        thread = c.string("thread")
        senderRole = c.string("senderRole")
        sender = c.string("sender")
        text = c.string("text")
        read = c.bool("read")
        created = c.string("created")
    }

    /// The server marks the other side as "partner".
    var isMine: Bool { sender != "partner" }
}

struct CreateThreadResponse: Decodable, Sendable {
    var threadId = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        threadId = c.string("threadId")
    }
}

// MARK: - AI

struct AiStatus: Decodable, Sendable {
    var enabled = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        enabled = c.bool("enabled")
    }
}

struct AiMessage: Codable, Hashable, Sendable {
    var role: String
    var content: String
}
