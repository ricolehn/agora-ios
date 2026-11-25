import Foundation

/// Event form content sent to POST/PATCH /api/events.
struct EventInput: Sendable {
    var title = ""
    var date = ""
    var endDate = ""
    var startTime = ""
    var endTime = ""
    var location = ""
    var description = ""
    var eventType = "event"
    var isPinned = false
    var requiresRegistration = false
    var minParticipants = 0
    var maxParticipants = 0
    var targetGroups: [String] = []
    var imageUrl = ""
    var isRecurring = false
    var recurringRule = "weekly"
    var recurringCount = 4
    var duties: [String] = []
    /// Made by someone who manages events: only they send the kind, pinning and repetition (API v2 refuses them from
    /// anyone else).
    var managed = false
}

/// How approving or rejecting a request ended.
enum RequestDecision: Sendable {
    case done
    /// Approved or rejected meanwhile (another treasurer, a second device): nothing was booked.
    case alreadyDecided
    /// The amount of the request cannot be read: it is not booked as 0 €, the request stays open.
    case unreadableAmount
}

/// All server calls of the app; mirrors the Android `AgoraRepository` so both clients write identical records.
final class Repository: Sendable {
    let api: APIClient
    /// API v2 of the server (CALDERA) and the books through it.
    let v2: ApiV2
    let books: BooksV2

    init(api: APIClient) {
        self.api = api
        v2 = ApiV2(api: api)
        books = BooksV2(v2: v2)
    }

    /// Asks the current server again what it answers, and whether the app goes through its API v2: the server lists v2
    /// (CALDERA) and – asked signed in – offers every resource the app uses (`ApiV2.needed`; the betas of CALDERA had
    /// only parts of it and are asked the old way throughout). Like Android's `checkServer`. No answer about v2 – the
    /// network failed, the server is starting (503), too many requests, an error in between – leaves it as it was: no
    /// switching APIs back and forth on a bad connection, which would leave what is open with the other API's ids.
    @discardableResult
    func checkServer() async -> StatusResponse? {
        guard let status: StatusResponse = try? await api.send(.get, "/api/status", reportUnauthorized: false) else { return nil }
        if !status.answersV2 || api.token == nil {
            api.apiV2 = false
        } else {
            do {
                api.apiV2 = try await v2.offersAll()
            } catch let error as APIError where error.status == 0 || error.status == 429 || error.status >= 500 {
                // as it was
            } catch {
                api.apiV2 = false
            }
        }
        return status
    }

    /// [newWay] through API v2 where the server answers it, else [oldWay] – also when it turns out that it does not (a
    /// server that went back to an older version): nothing was done through v2 then.
    func v2Or<T>(_ newWay: () async throws -> T, _ oldWay: () async throws -> T) async throws -> T {
        guard v2.available else { return try await oldWay() }
        do {
            return try await newWay()
        } catch is V2Unavailable {
            return try await oldWay()
        }
    }

    /// A change of something read through API v2 (its ids are v2's): a server that answers no v2 any more says it
    /// changed – the screen reads it anew – instead of writing it the old way under ids the old API does not know.
    private func changeV2(_ change: () async throws -> Void) async throws {
        do {
            try await change()
        } catch is V2Unavailable {
            throw APIError(status: 409, message: "Conflict", code: "conflict")
        }
    }

    // MARK: Server & auth

    func status(baseURL: String) async throws -> StatusResponse {
        api.baseURL = baseURL
        return try await api.send(.get, "/api/status", reportUnauthorized: false)
    }

    /// App name from the web app's config module (`appName: "..."`).
    func appName() async -> String? {
        guard let script = try? await api.text("/assets/config.js") else { return nil }
        guard let range = script.range(of: #"appName:\s*"((?:[^"\\]|\\.)*)""#, options: .regularExpression) else { return nil }
        let match = String(script[range])
        guard let start = match.firstIndex(of: "\""), let end = match.lastIndex(of: "\""), start < end else { return nil }
        let quoted = String(match[start...end])
        return (try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))) ?? String(quoted.dropFirst().dropLast())
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await api.send(.post, "/api/auth/login",
                           body: ["email": .string(email.trimmingCharacters(in: .whitespaces)), "password": .string(password)],
                           reportUnauthorized: false)
    }

    func register(code: String, email: String, firstName: String, lastName: String, password: String) async throws -> AuthResponse {
        try await api.send(.post, "/api/auth/register", body: [
            "inviteCode": .string(code.trimmingCharacters(in: .whitespaces)),
            "email": .string(email.trimmingCharacters(in: .whitespaces)),
            "firstName": .string(firstName.trimmingCharacters(in: .whitespaces)),
            "lastName": .string(lastName.trimmingCharacters(in: .whitespaces)),
            "password": .string(password)
        ], reportUnauthorized: false)
    }

    func me() async throws -> User {
        let response: AuthResponse = try await api.get("/api/auth/me")
        guard let user = response.user else { throw APIError(status: 401, message: "Unauthorized") }
        return user
    }

    func logout() async {
        try? await api.perform(.post, "/api/auth/logout")
    }

    func changePassword(old: String, new: String) async throws {
        try await api.perform(.post, "/api/auth/password", body: ["oldPassword": .string(old), "password": .string(new)])
    }

    /// Deletes the own account and its personal data (App Store guideline 5.1.1(v)).
    func deleteAccount(password: String) async throws {
        try await api.perform(.post, "/api/auth/delete-account", body: ["password": .string(password)])
    }

    /// Reports an AI reply ("ai") or a conversation ("chat") to the admins.
    func report(type: String, content: String, reason: String, prompt: String = "", threadId: String = "") async throws {
        var body: JSONValue = ["type": .string(type), "content": .string(content), "reason": .string(reason)]
        if !prompt.isEmpty { body["prompt"] = .string(prompt) }
        if !threadId.isEmpty { body["threadId"] = .string(threadId) }
        try await api.perform(.post, "/api/reports", body: body)
    }

    // MARK: Profile & settings

    func uploadProfilePicture(jpeg: Data) async throws {
        let _: JSONValue = try await api.upload("/api/profile/picture",
                                                file: .init(field: "picture", fileName: "profile.jpg", mimeType: "image/jpeg", data: jpeg))
    }

    func profilePictureURL(_ uid: String) -> URL? { uid.isEmpty ? nil : api.absolute("/api/profile/picture/\(uid)") }

    /// Saves channels and kinds like the web (the flat keys repeat the push choice for older servers and apps).
    func saveNotificationSettings(uid: String, _ prefs: NotificationPrefs) async throws {
        var settings = prefs.push.json
        settings["channels"] = ["push": .bool(prefs.channels.push), "email": .bool(prefs.channels.email)]
        settings["push"] = prefs.push.json
        settings["email"] = prefs.email.json
        try await api.perform(.patch, "/api/db", body: [
            "path": .string("users/\(uid)"),
            "value": [
                "notificationSettings": settings,
                "emailNotifications": .bool(prefs.channels.push || prefs.channels.email)
            ]
        ])
    }

    /// Reports the device's time zone, so the server times duty reminders in local time (only when it changed).
    func syncTimeZone(_ user: User) async throws {
        let zone = TimeZone.current.identifier
        guard !zone.isEmpty, zone != user.timeZone, !user.userId.isEmpty else { return }
        try await api.perform(.patch, "/api/db", body: ["path": .string("users/\(user.userId)"), "value": ["timeZone": .string(zone)]])
    }

    func calendarFeed() async throws -> CalendarFeed {
        try await v2Or({ try await v2.call(.get, "/calendar-feed") }, { try await api.get("/api/user/calendar-feed") })
    }

    func resetCalendarFeed() async throws -> CalendarFeed {
        try await v2Or({ try await v2.call(.post, "/calendar-feed/reset") }, { try await api.send(.post, "/api/user/calendar-feed/reset") })
    }

    func inviteCode() async -> String? {
        guard let value: JSONValue = try? await api.get("/api/db", query: ["path": "system/inviteCode"]) else { return nil }
        return value.text
    }

    func setInviteCode(_ code: String) async throws {
        try await api.perform(.put, "/api/db", body: ["path": "system/inviteCode", "value": .string(code)])
    }

    /// The fees of this month per status: through API v2 from the fees over time (`GET /fees`, `currentCents`).
    func feeSettings() async throws -> FeeSettings {
        try await v2Or({
            let fees: JSONValue = try await v2.call(.get, "/fees")
            let current = fees["currentCents"]?.objectValue ?? [:]
            return FeeSettings(rates: current.compactMapValues { value in value.amount.map { $0 / 100 } })
        }, { try await api.get("/api/db", query: ["path": "settings"]) })
    }

    /// The settings object is written as a whole: without reading it first nothing is written (it also holds the
    /// rate of "pausiert" and the report start date).
    func saveFeeSettings(_ rates: [String: Double]) async throws {
        var current: JSONValue = try await api.get("/api/db", query: ["path": "settings"])
        if current.isNull { current = [:] }
        guard current.objectValue != nil else { throw APIError(status: 0, message: APIError.generic) }
        for (key, value) in rates { current[key] = .number(value) }
        try await api.perform(.put, "/api/db", body: ["path": "settings", "value": current])
    }

    func groups() async -> [MemberGroup] {
        (try? await v2Or({ try await v2.all("/groups", of: MemberGroup.self).items },
                         { try await api.get("/api/groups", as: LossyList<MemberGroup>.self).items })) ?? []
    }

    // MARK: Finances (member)

    /// The member records of the account [uid] (its own: one), with payments, standing orders and status history.
    func ownPeople(uid: String) async throws -> [Person] {
        try await v2Or({
            var own: [Person] = []
            for member in try await books.members().values where member.userId == uid && !member.isDeleted {
                own.append(try await books.member(member.id).toPerson())
            }
            return own
        }, {
            let collection: KeyedCollection<Person> = try await api.get("/api/db", query: ["path": "people", "orderByChild": "uid", "equalTo": uid])
            return collection.items.filter { !$0.isDeleted }
        })
    }

    /// Every member record with its fee account (through API v2 without their payments: `person(id:)` reads one whole).
    func allPeople() async throws -> [Person] {
        let people = try await v2Or({
            try await books.members().values.filter { !$0.isDeleted }.map { $0.toPerson() }
        }, {
            let collection: KeyedCollection<Person> = try await api.get("/api/db", query: ["path": "people"])
            return collection.items.filter { !$0.isDeleted }
        })
        return people.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One member record, by the key the old API knows it by, with payments, standing orders and status history.
    func person(id: String) async throws -> Person? {
        try await v2Or({
            guard let member = try await books.memberByKey(id) else { return nil }
            return try await books.member(member.id).toPerson()
        }, {
            let value: JSONValue = try await api.get("/api/db", query: ["path": "people/\(id)"])
            guard !value.isNull, value.objectValue != nil else { return nil }
            return try? api.decoder.decode(Person.self, from: api.encoder.encode(value))
        })
    }

    /// The requests the person may see (treasurers all of them, members their own), newest first.
    func allRequests() async throws -> [FinanceRequest] {
        try await v2Or({ try await books.requests() }, {
            let collection: KeyedCollection<FinanceRequest> = try await api.get("/api/db", query: ["path": "requests"])
            return collection.items.sorted { $0.timestamp > $1.timestamp }
        })
    }

    /// Uploads a receipt; for the old API name and date go first because the server builds the stored file name from them.
    func uploadReceipt(ownerName: String, date: String, fileName: String, mimeType: String, data: Data) async throws -> String {
        try await v2Or({
            try await books.uploadReceipt(fileName: fileName, mimeType: mimeType, data: data)
        }, {
            let response: UploadResponse = try await api.upload("/api/upload", fields: [("name", ownerName), ("date", date)],
                                                                 file: .init(field: "receipt", fileName: fileName, mimeType: mimeType, data: data))
            return response.filename
        })
    }

    /// Receipt names come from request data members write: only a plain file name, encoded, goes into the path.
    func receiptURL(_ fileName: String) -> URL? {
        let name = fileName.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        guard !name.isEmpty, name != ".", name != "..",
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
        return api.absolute((v2.available ? ApiV2.base + "/receipts/" : "/api/receipts/") + encoded)
    }

    /// Member → treasurer application about the member's own record [person] (through API v2 named by its id where it was
    /// read there, and the server tells the treasurers itself); through the old API the client notifies the admins.
    func submitRequest(user: User, person: Person?, type: String, data: [String: JSONValue]) async throws {
        let told = try await v2Or({
            try await books.ask(type: type, details: data, memberId: person?.memberId)
            return true
        }, {
            try await submitRequestOld(user: user, person: person, type: type, data: data)
            return false
        })
        if !told {
            try? await api.perform(.post, "/api/notify-admins", body: ["reqType": .string(type), "personName": .string(person?.name ?? user.fullName)])
        }
    }

    private func submitRequestOld(user: User, person: Person?, type: String, data: [String: JSONValue]) async throws {
        let id = String(Int64(Date().timeIntervalSince1970 * 1000))
        let personName = person?.name ?? user.fullName
        try await api.perform(.put, "/api/db", body: [
            "path": .string("requests/\(id)"),
            "value": [
                "id": .string(id),
                "type": .string(type),
                "userId": .string(user.userId),
                "personId": .string(person?.id ?? user.userId),
                "personName": .string(personName),
                "data": .object(data),
                "status": "pending",
                "timestamp": .number(Double(id) ?? 0)
            ]
        ])
    }

    // MARK: Finances (treasurer)

    func stats() async throws -> FinanceStats {
        try await v2Or({ try await books.summary() }, { try await api.get("/api/stats") })
    }

    /// One page of the history, newest first, after [cursor] (nil: the first); with [search] only what the server finds.
    /// Through API v2 the pages follow a cursor, through the old API they are numbered.
    func history(search: String, after cursor: HistoryCursor?) async throws -> (items: [Transaction], next: HistoryCursor?) {
        switch cursor {
        case .page(let page)?:
            return try await historyOld(search: search, page: page)
        case .v2(let after)?:
            let page = try await books.history(search: search, cursor: after)
            return (page.items, page.next.map(HistoryCursor.v2))
        case nil:
            return try await v2Or({
                let page = try await books.history(search: search, cursor: nil)
                return (page.items, page.next.map(HistoryCursor.v2))
            }, { try await historyOld(search: search, page: 1) })
        }
    }

    private func historyOld(search: String, page: Int) async throws -> (items: [Transaction], next: HistoryCursor?) {
        let result: TransactionPage = try await api.get("/api/transactions", query: ["page": String(page), "perPage": "50", "search": search])
        return (result.items, result.page < result.totalPages ? .page(result.page + 1) : nil)
    }

    /// Every booking (all pages), for the financial report.
    func allTransactions() async throws -> [Transaction] {
        try await v2Or({ try await books.allBookings() }, { try await allTransactionsOld() })
    }

    private func allTransactionsOld() async throws -> [Transaction] {
        var all: [Transaction] = []
        var page = 1
        var pages = 1
        repeat {
            let result: TransactionPage = try await api.get("/api/transactions", query: ["page": String(page), "perPage": "500"])
            all += result.items
            pages = max(result.totalPages, 1)
            page += 1
        } while page <= pages
        return all
    }

    /// Optimistic-locking update of a person record, like the web app's runTransaction (3 attempts).
    func mutatePerson(id: String, _ mutate: (JSONValue) throws -> JSONValue) async throws {
        for attempt in 0..<3 {
            let raw: JSONValue = try await api.get("/api/db", query: ["path": "people/\(id)", "raw": "1"])
            guard var current = raw["value"], current.objectValue != nil else { throw APIError(status: 404, message: "Person nicht gefunden") }
            if current["payments"]?.arrayValue == nil { current["payments"] = .array([]) }
            if current["statusHistory"]?.arrayValue == nil { current["statusHistory"] = .array([]) }
            do {
                try await api.perform(.post, "/api/db/transaction", body: [
                    "path": .string("people/\(id)"),
                    "currentVersion": raw["version"] ?? .null,
                    "value": try mutate(current)
                ])
                return
            } catch let error as APIError where error.status == 409 && attempt < 2 {
                continue
            }
        }
    }

    /// Donations and expenses are stored as whole lists: read the list with its version, change it, write it back with
    /// that version ([change] nil: nothing to write), like Android. A list someone else saved meanwhile is refused (409)
    /// and read and changed again – without the version, an entry the web or Android added in between was lost. Servers
    /// before CALDERA send no version and save the list as before.
    private func mutateCollection(_ name: String, _ change: ([JSONValue]) -> [JSONValue]?) async throws {
        for attempt in 0..<3 {
            let raw: JSONValue = try await api.get("/api/db", query: ["path": name, "raw": "1"])
            let list: [JSONValue]
            switch raw["value"] ?? .null {
            case .array(let items): list = items
            case .object(let map): list = map.keys.sorted().compactMap { map[$0] }
            default: list = []
            }
            guard let next = change(list.filter { !$0.isNull }) else { return }
            var body: JSONValue = ["path": .string(name), "value": .array(next)]
            if let version = raw["version"]?.text, !version.isEmpty { body["version"] = .string(version) }
            do {
                try await api.perform(.put, "/api/db", body: body)
                return
            } catch let error as APIError where error.status == 409 && attempt < 2 {
                // A short random pause, so devices that collided do not collide again
                try? await Task.sleep(nanoseconds: UInt64.random(in: 50_000_000...400_000_000))
                continue
            }
        }
    }

    private static func nowId() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Books a payment – or with [standingOrder] sets up a standing order – for [person]. Read through API v2 it goes
    /// there (a standing order's months up to today are booked at once by the server, as by the web app); otherwise
    /// through the member's record, as before.
    func bookPayment(person: Person, amount: Double, date: String, note: String, standingOrder: Bool) async throws {
        if let memberId = person.memberId, v2.available {
            return try await changeV2 {
                if standingOrder {
                    try await books.addStandingOrder(memberId: memberId, version: person.version, amountCents: cents(amount), startDate: date, note: note)
                } else {
                    try await books.addPayment(memberId: memberId, version: person.version, amountCents: cents(amount), date: date, description: note)
                }
            }
        }
        try await mutatePerson(id: person.id) { person in
            if standingOrder {
                return PersonRecord.append(person, to: "standingOrders", [
                    "id": .string(String(Int64(Self.nowId()))), "amount": .number(amount), "startDate": .string(date),
                    "note": .string(note), "lastAutoPayment": .null
                ])
            }
            let updated = PersonRecord.append(person, to: "payments", [
                "amount": .number(amount), "date": .string(date), "description": .string(note), "id": .number(Self.nowId())
            ])
            return PersonRecord.addingToTotal(updated, amount)
        }
    }

    /// Ends a standing order on [endDate] (also retroactively). Read through API v2 the order has v2's id, which the old
    /// API does not know: it goes through v2 only.
    func endStandingOrder(person: Person, orderId: String, endDate: String) async throws {
        if let memberId = person.memberId {
            return try await changeV2 { try await books.endStandingOrder(memberId: memberId, version: person.version, orderId: orderId, endDate: endDate) }
        }
        try await mutatePerson(id: person.id) { StandingOrders.end($0, orderId: orderId, endDate: endDate, today: Day.today()) }
    }

    /// Removes the standing order entry; payments it already booked stay. Read through v2: as `endStandingOrder`.
    func deleteStandingOrder(person: Person, orderId: String) async throws {
        if let memberId = person.memberId {
            return try await changeV2 { try await books.deleteStandingOrder(memberId: memberId, version: person.version, orderId: orderId) }
        }
        try await mutatePerson(id: person.id) { StandingOrders.remove($0, orderId: orderId) }
    }

    /// [person]'s income status from [date] on (the history is rewritten as the web app does: through v2 by the server).
    func changeStatus(person: Person, status: String, date: String) async throws {
        if let memberId = person.memberId, v2.available {
            return try await changeV2 { try await books.changeStatus(memberId: memberId, version: person.version, status: status, date: date) }
        }
        try await mutatePerson(id: person.id) { try StatusHistory.apply($0, newStatus: status, changeDate: date) }
    }

    func addDonation(amount: Double, name: String, date: String, description: String) async throws {
        try await v2Or({
            try await books.addDonation(amountCents: cents(amount), date: date, donorName: name,
                                        description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        }, { try await addDonationOld(amount: amount, name: name, date: date, description: description) })
    }

    private func addDonationOld(amount: Double, name: String, date: String, description: String) async throws {
        try await mutateCollection("donations") { $0 + [[
            "amount": .number(amount), "name": .string(name), "date": .string(date),
            "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)), "id": .number(Self.nowId())
        ]] }
    }

    func addExpense(amount: Double, issuer: String, date: String, description: String, receipts: [String]) async throws {
        try await v2Or({
            try await books.addExpense(amountCents: cents(amount), date: date, issuer: issuer, description: description, receipts: receipts)
        }, { try await addExpenseOld(amount: amount, issuer: issuer, date: date, description: description, receipts: receipts) })
    }

    private func addExpenseOld(amount: Double, issuer: String, date: String, description: String, receipts: [String]) async throws {
        let receipt: JSONValue = receipts.isEmpty ? .null
            : .string(String(decoding: (try? JSONEncoder().encode(receipts)) ?? Data("[]".utf8), as: UTF8.self))
        try await mutateCollection("expenses") { $0 + [[
            "amount": .number(amount), "issuer": .string(issuer), "description": .string(description),
            "date": .string(date), "id": .number(Self.nowId()), "receipt": receipt
        ]] }
    }

    /// Whether the request is still open on the server: the list on screen can be older than a decision made elsewhere.
    private func isPending(_ requestId: String) async throws -> Bool {
        guard !requestId.isEmpty else { return false }
        let value: JSONValue = try await api.get("/api/db", query: ["path": "requests/\(requestId)"])
        guard value.objectValue != nil else { return false }
        return (value["status"]?.text ?? "pending") == "pending"
    }

    /// Books an approved request and marks it approved, like the web app. Approving a request twice (two treasurers, a
    /// second device, a retry) used to book the money twice: only a pending request is booked, and the booking carries
    /// the request's id, so a request that is booked already changes nothing (`RequestBookings`).
    func approveRequest(_ request: FinanceRequest) async throws -> RequestDecision {
        guard request.v2 else { return try await approveRequestOld(request) }
        return try await v2Or({ try await approveRequestV2(request) }, { try await approveRequestOld(request) })
    }

    /// Through API v2 the request is decided and booked in one step, as the web app books it – the payment, the expense
    /// with its receipts, the standing order (its months up to today) or the status change: once, however often it is
    /// sent. Decided meanwhile by someone else (409), an approval keeps its booking, after a rejection the server takes
    /// back what this call booked. What cannot be booked as it is stays open for the treasury to book by hand.
    private func approveRequestV2(_ request: FinanceRequest) async throws -> RequestDecision {
        do {
            try await books.decide(id: request.id, status: "approved", book: true)
            return .done
        } catch let error as APIError where error.status == 409 || error.status == 404 {
            // Decided already, or gone with the cleanup of decided requests
            return .alreadyDecided
        } catch let error as APIError where error.status == 400 && error.field == "details.amount" {
            return .unreadableAmount
        }
    }

    private func approveRequestOld(_ request: FinanceRequest) async throws -> RequestDecision {
        guard try await isPending(request.id) else { return .alreadyDecided }
        let amount = request.data["amount"]?.amount
        if amount == nil && request.type != "status" { return .unreadableAmount }
        var before: JSONValue?
        if request.type == "expense" {
            try await mutateCollection("expenses") { RequestBookings.addingExpense($0, request: request, amount: amount ?? 0) }
        } else {
            try await mutatePerson(id: request.personId) { person in
                before = person
                return try RequestBookings.apply(person, request: request, amount: amount ?? 0)
            }
        }
        do {
            try await patchRequest(request.id, ["status": "approved"])
        } catch let error as APIError where error.status == 409 {
            // Rejected by someone else between the check and now (the server keeps the first decision): the booking
            // is taken back
            if request.type == "expense" {
                try await mutateCollection("expenses") { RequestBookings.removingExpense($0, request: request) }
            } else {
                let booked = before
                try await mutatePerson(id: request.personId) { RequestBookings.removingBooking($0, request: request, before: booked) }
            }
            return .alreadyDecided
        }
        return .done
    }

    func rejectRequest(_ request: FinanceRequest, reason: String) async throws -> RequestDecision {
        let text = reason.trimmingCharacters(in: .whitespaces)
        if request.v2 {
            let decided: RequestDecision? = try await v2Or({
                do {
                    // Without a reason v2 words it itself
                    try await books.decide(id: request.id, status: "rejected", rejectionReason: text.isEmpty ? nil : text)
                    return .done
                } catch let error as APIError where error.status == 409 || error.status == 404 {
                    return .alreadyDecided
                }
            }, { nil })
            if let decided { return decided }
        }
        return try await rejectRequestOld(id: request.id, reason: reason)
    }

    private func rejectRequestOld(id: String, reason: String) async throws -> RequestDecision {
        guard try await isPending(id) else { return .alreadyDecided }
        let text = reason.trimmingCharacters(in: .whitespaces)
        do {
            try await patchRequest(id, ["status": "rejected", "rejectionReason": .string(text.isEmpty ? "Kein Grund angegeben" : text)])
        } catch let error as APIError where error.status == 409 {
            return .alreadyDecided
        }
        return .done
    }

    private func patchRequest(_ id: String, _ value: JSONValue) async throws {
        try await api.perform(.patch, "/api/db", body: ["path": .string("requests/\(id)"), "value": value])
    }

    // MARK: Events

    /// A value of v2 in the old API's shape (V2Calendar) read as the app's model.
    private func model<T: Decodable>(_ value: JSONValue, as type: T.Type = T.self) throws -> T {
        try api.decoder.decode(T.self, from: api.encoder.encode(value))
    }

    func events() async throws -> [AgoraEvent] {
        try await v2Or({
            try await v2.all("/events", of: JSONValue.self).items.compactMap { try? model(V2Calendar.event($0), as: AgoraEvent.self) }
        }, { try await api.get("/api/events", as: LossyList<AgoraEvent>.self).items })
    }

    func myDutyRequests() async throws -> [DutyRequest] {
        try await v2Or({
            try await v2.all("/duty-requests", of: JSONValue.self).items.compactMap { try? model(V2Calendar.dutyRequest($0), as: DutyRequest.self) }
        }, { try await api.get("/api/events/my-requests", as: LossyList<DutyRequest>.self).items })
    }

    /// CALDERA has no such setting any more: every member may create events (as through v2, like Android).
    func eventSettings() async -> EventSettings {
        if v2.available { return EventSettings() }
        return (try? await api.get("/api/events/settings")) ?? EventSettings()
    }

    func attendees(eventId: String) async throws -> Attendees {
        try await v2Or({
            try model(V2Calendar.attendees(try await v2.all("/events/\(ApiV2.segment(eventId))/participants", of: JSONValue.self).items))
        }, { try await api.get("/api/events/\(eventId)/attendees") })
    }

    func candidates() async throws -> Candidates {
        try await v2Or({
            async let people = v2.all("/people", of: JSONValue.self).items
            async let groups = v2.all("/groups", of: JSONValue.self).items
            return try model(V2Calendar.candidates(people: try await people, groups: try await groups))
        }, { try await api.get("/api/events/candidates") })
    }

    func register(eventId: String, _ register: Bool) async throws {
        try await v2Or({
            try await v2.perform(register ? .put : .delete, "/events/\(ApiV2.segment(eventId))/registration")
        }, {
            try await api.perform(.post, "/api/events/\(eventId)/register", body: ["action": .string(register ? "register" : "cancel")])
        })
    }

    /// Members by account id, guests (server v3.2+) by "guest:<id>".
    func removeAttendee(eventId: String, userId: String) async throws {
        try await v2Or({
            try await v2.perform(.delete, "/events/\(ApiV2.segment(eventId))/participants/\(ApiV2.segment(userId))")
        }, { try await api.perform(.delete, "/api/events/\(eventId)/attendees/\(userId)") })
    }

    /// The share switch: whether people without an account may open the event's link (only its editors).
    func setEventPublic(eventId: String, _ isPublic: Bool) async throws {
        try await v2Or({
            try await v2.perform(.patch, "/events/\(ApiV2.segment(eventId))", body: ["isPublic": .bool(isPublic)])
        }, { try await api.perform(.patch, "/api/events/\(eventId)", body: ["isPublic": .bool(isPublic)]) })
    }

    func respondToDuty(id: String, accept: Bool) async throws {
        try await v2Or({
            try await v2.perform(.post, "/duties/\(ApiV2.segment(id))/answer", body: ["answer": .string(accept ? "accept" : "decline")])
        }, { try await api.perform(.post, "/api/events/duties/\(id)/respond", body: ["action": .string(accept ? "accept" : "decline")]) })
    }

    /// Takes an open duty (or one asked of oneself) / gives it back.
    func claimDuty(id: String, claim: Bool) async throws {
        try await v2Or({
            try await v2.perform(claim ? .put : .delete, "/duties/\(ApiV2.segment(id))/claim")
        }, { try await api.perform(.post, "/api/events/duties/\(id)/claim", body: claim ? [:] : ["action": "unclaim"]) })
    }

    func cancelDutyRequest(id: String) async throws {
        try await v2Or({ try await v2.perform(.delete, "/duties/\(ApiV2.segment(id))/request") },
                       { try await api.perform(.post, "/api/events/duties/\(id)/cancel-request") })
    }

    /// A duty asked of a person ([userId]: by push and e-mail), given to a group ([groupId]) or open.
    func addDuty(eventId: String, roleName: String, section: String = "", userId: String? = nil, groupId: String? = nil) async throws {
        try await v2Or({
            var body: JSONValue = ["roleName": .string(roleName), "sendEmail": true]
            if !section.isEmpty { body["section"] = .string(section) }
            if let userId { body["requestedUserId"] = .string(userId) }
            if let groupId { body["assignedGroupId"] = .string(groupId) }
            try await v2.perform(.post, "/events/\(ApiV2.segment(eventId))/duties", body: body)
        }, {
            var body: JSONValue = ["roleName": .string(roleName), "sendEmail": true]
            if !section.isEmpty { body["section"] = .string(section) }
            if let userId { body["targetUserId"] = .string(userId) }
            if let groupId { body["targetGroupId"] = .string(groupId) }
            try await api.perform(.post, "/api/events/\(eventId)/duties", body: body)
        })
    }

    /// Gives a duty to a group or asks a person.
    func assignDuty(id: String, userId: String?, groupId: String?) async throws {
        try await v2Or({
            var body: JSONValue = ["sendEmail": true]
            if let userId { body["userId"] = .string(userId) }
            if let groupId { body["groupId"] = .string(groupId) }
            try await v2.perform(.post, "/duties/\(ApiV2.segment(id))/assignment", body: body)
        }, {
            var body: JSONValue = ["sendEmail": true]
            if let userId { body["targetUserId"] = .string(userId) }
            if let groupId { body["targetGroupId"] = .string(groupId) }
            try await api.perform(.post, "/api/events/duties/\(id)/assign", body: body)
        })
    }

    func updateDutyNotes(id: String, notes: String) async throws {
        try await v2Or({ try await v2.perform(.patch, "/duties/\(ApiV2.segment(id))", body: ["notes": .string(notes)]) },
                       { try await api.perform(.patch, "/api/events/duties/\(id)", body: ["notes": .string(notes)]) })
    }

    func deleteDuty(id: String) async throws {
        try await v2Or({ try await v2.perform(.delete, "/duties/\(ApiV2.segment(id))") },
                       { try await api.perform(.delete, "/api/events/duties/\(id)") })
    }

    func uploadEventImage(jpeg: Data) async throws -> String {
        let file = APIClient.FilePart(field: "image", fileName: "cover.jpg", mimeType: "image/jpeg", data: jpeg)
        return try await v2Or({
            let image: JSONValue = try await v2.upload("/events/images", file: file)
            return image["url"]?.text ?? ""
        }, {
            let response: UploadResponse = try await api.upload("/api/events/upload-image", file: file)
            return response.url
        })
    }

    /// A new event ([existingId] nil: with its duties – every date of a series gets them) or a change of one.
    /// Appointments, pinned and repeated events are for those who manage events.
    func saveEvent(id existingId: String?, _ input: EventInput) async throws {
        try await v2Or({ try await saveEventV2(id: existingId, input) }, { try await saveEventOld(id: existingId, input) })
    }

    private func saveEventV2(id existingId: String?, _ input: EventInput) async throws {
        var body: JSONValue = [
            "title": .string(input.title.trimmingCharacters(in: .whitespaces)),
            "date": .string(input.date), "endDate": .string(input.endDate),
            "startTime": .string(input.startTime), "endTime": .string(input.endTime),
            "location": .string(input.location.trimmingCharacters(in: .whitespaces)),
            "description": .string(input.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "requiresRegistration": .bool(input.requiresRegistration),
            "minParticipants": .of(input.minParticipants), "maxParticipants": .of(input.maxParticipants),
            "targetGroups": .of(input.targetGroups), "imageUrl": .string(input.imageUrl)
        ]
        if input.managed {
            body["kind"] = .string(input.eventType)
            body["isPinned"] = .bool(input.isPinned)
        }
        if existingId == nil {
            if input.isRecurring, input.managed {
                body["recurrence"] = ["rule": .string(input.recurringRule), "count": .of(input.recurringCount)]
            }
            if !input.duties.isEmpty { body["duties"] = .array(input.duties.map { ["roleName": .string($0)] }) }
        }
        if let existingId {
            try await v2.perform(.patch, "/events/\(ApiV2.segment(existingId))", body: body)
        } else {
            try await v2.perform(.post, "/events", body: body)
        }
    }

    private func saveEventOld(id existingId: String?, _ input: EventInput) async throws {
        var body: JSONValue = [
            "title": .string(input.title.trimmingCharacters(in: .whitespaces)),
            "date": .string(input.date), "endDate": .string(input.endDate),
            "startTime": .string(input.startTime), "endTime": .string(input.endTime),
            "location": .string(input.location.trimmingCharacters(in: .whitespaces)),
            "description": .string(input.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "eventType": .string(input.eventType), "isPinned": .bool(input.isPinned),
            "requiresRegistration": .bool(input.requiresRegistration),
            "minParticipants": .of(input.minParticipants), "maxParticipants": .of(input.maxParticipants),
            "targetGroups": .of(input.targetGroups), "imageUrl": .string(input.imageUrl)
        ]
        if existingId == nil {
            body["isRecurring"] = .bool(input.isRecurring)
            if input.isRecurring {
                body["recurringRule"] = .string(input.recurringRule)
                body["recurringCount"] = .of(input.recurringCount)
            }
            if !input.duties.isEmpty { body["duties"] = .array(input.duties.map { ["roleName": .string($0)] }) }
        }
        if let existingId {
            try await api.perform(.patch, "/api/events/\(existingId)", body: body)
        } else {
            try await api.perform(.post, "/api/events", body: body)
        }
    }

    func deleteEvent(id: String) async throws {
        try await v2Or({ try await v2.perform(.delete, "/events/\(ApiV2.segment(id))") },
                       { try await api.perform(.delete, "/api/events/\(id)") })
    }

    // MARK: Mentoring

    func threads() async throws -> [MentoringThread] { try await api.get("/api/mentoring/threads", as: LossyList<MentoringThread>.self).items }

    func messages(threadId: String) async throws -> [ChatMessage] {
        try await api.get("/api/mentoring/threads/\(threadId)/messages", as: LossyList<ChatMessage>.self).items
    }

    func sendMessage(threadId: String, text: String) async throws {
        try await api.perform(.post, "/api/mentoring/threads/\(threadId)/messages", body: ["text": .string(text)])
    }

    /// "closed", "active" (reopen) or "blocked".
    func setThreadStatus(threadId: String, _ status: String) async throws {
        try await api.perform(.patch, "/api/mentoring/threads/\(threadId)/status", body: ["status": .string(status)])
    }

    func mentors(status: String? = nil) async throws -> [Mentor] {
        try await api.get("/api/mentoring/mentors", query: status.map { ["status": $0] } ?? [:], as: LossyList<Mentor>.self).items
    }

    func myMentorProfile() async -> MyMentorProfile { (try? await api.get("/api/mentoring/my-profile")) ?? MyMentorProfile() }

    func contactMentor(userId: String, message: String) async throws -> String {
        let response: CreateThreadResponse = try await api.send(.post, "/api/mentoring/threads",
                                                                body: ["mentorId": .string(userId), "initialMessage": .string(message)])
        return response.threadId
    }

    func saveMentorProfile(isNew: Bool, bio: String, maxMentees: Int, isAccepting: Bool) async throws {
        var body: JSONValue = ["bio": .string(bio.trimmingCharacters(in: .whitespacesAndNewlines)), "max_mentees": .of(maxMentees)]
        if !isNew { body["isAccepting"] = .bool(isAccepting) }
        if isNew {
            try await api.perform(.post, "/api/mentoring/apply", body: body)
        } else {
            try await api.perform(.put, "/api/mentoring/my-profile", body: body)
        }
    }

    func setMentorStatus(recordId: String, _ status: String) async throws {
        try await api.perform(.post, "/api/mentoring/manage/\(recordId)/status", body: ["status": .string(status)])
    }

    // MARK: AI

    func aiEnabled() async -> Bool { ((try? await api.get("/api/admin/ai-status", as: AiStatus.self))?.enabled) ?? false }

    /// Streams an AI answer (`data: {"content"|"reasoning"}` lines ending with `data: [DONE]`).
    func aiChat(history: [AiMessage]) throws -> AsyncThrowingStream<AiChunk, Error> {
        var request = api.request(try api.url("/api/ai/chat"), method: .post)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try api.encoder.encode(JSONValue.object(["messages": .array(history.map { ["role": .string($0.role), "content": .string($0.content)] })]))
        let lines = api.lines(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: Data(payload.utf8)) else { continue }
                        for chunk in AiChunk.of(object) { continuation.yield(chunk) }
                        if let error = object["error"]?.text { throw APIError(status: 500, message: error) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Live updates

    /// Changed areas ("all", "events", "mentoring") per `data_update` event; reconnects with backoff until cancelled.
    /// Servers before 3.0.0-beta15 send no scope: that counts as "all".
    func liveUpdates() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                var backoff: UInt64 = 2
                while !Task.isCancelled {
                    do {
                        let request = api.request(try api.url("/api/stream"))
                        var isUpdate = false
                        for try await line in api.lines(request) {
                            backoff = 2
                            if line.hasPrefix("event:") {
                                isUpdate = line.contains("data_update")
                            } else if line.hasPrefix("data:"), isUpdate {
                                continuation.yield(Self.updateScope(String(line.dropFirst(5))))
                                isUpdate = false
                            }
                        }
                    } catch let error as APIError where error.status == 401 {
                        break
                    } catch {
                        // network hiccup or proxy closing the idle connection: retry below
                    }
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                    backoff = min(backoff * 2, 60)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func updateScope(_ payload: String) -> String {
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: Data(payload.trimmingCharacters(in: .whitespaces).utf8)),
              let scope = object["scope"]?.text, !scope.isEmpty else { return "all" }
        return scope
    }
}
