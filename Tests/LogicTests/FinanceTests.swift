import Foundation

/// Money rules shared with the web app (assets/finance.js, tests/finance.test.js in agora) and Android (LogicTest.kt).
enum FinanceTests {
    static let all: [TestCase] = [
        TestCase("typed amounts are read as typed, ambiguous ones refused (web cases)") {
            let cases: [(String, Double)] = [
                ("50", 50), ("12,5", 12.5), ("1234,56", 1234.56), ("1234.56", 1234.56), ("1.234,56", 1234.56),
                ("1,234.56", 1234.56), ("1 234,56", 1234.56), ("50 €", 50), ("50 EUR", 50), ("50,-", 50), ("50.-", 50), ("50.", 50),
                (",50", 0.5), ("1.500,00", 1500), ("1.500,-", 1500), ("1.500.000", 1_500_000), ("-20", -20)
            ]
            for (typed, amount) in cases { expectClose(Amount.typed(typed), amount, typed) }
            // "1.500" means 1500 € in German and 1.5 in English: it used to be booked as 1,50 €
            for typed in ["1.500", "1,500", "2.000", "1.234.56", "1 234.567", "1e3", "abc", "", ",", "-"] {
                expectNil(Amount.typed(typed), typed)
            }
            expectNil(Amount.typed(nil))
            expect(Amount.isUnclear("1.500"))
            expect(!Amount.isUnclear(""), "an empty field is not unclear, just empty")
            expect(!Amount.isUnclear("1.500,00"))
        },
        TestCase("amount fields keep digits and the two separators only (like Android)") {
            expectEqual(Amount.typeable("1.500,00 €"), "1.500,00")
            expectEqual(Amount.typeable("12a,5"), "12,5")
            expectEqual(Amount.typeable("-20"), "20")
            expectEqual(Amount.typeable("٥٠"), "", "only ASCII digits, like the web app's \\d")
        },
        TestCase("status pickers preselect one of the four statuses") {
            expectEqual(MemberStatus.known("geringverdiener"), "geringverdiener")
            expectEqual(MemberStatus.known("pausiert"), "pausiert")
            expectEqual(MemberStatus.known("ehrenmitglied"), "vollverdiener")
            expectEqual(MemberStatus.known(nil), "vollverdiener")
        },
        TestCase("the fee list's own format reads back unchanged") {
            // SettingsView.amountText writes de_DE with two decimals
            for (text, amount) in [("1.500,00", 1500.0), ("50,00", 50), ("12,50", 12.5), ("1.234,56", 1234.56)] {
                expectClose(Amount.typed(text), amount, text)
            }
        },
        TestCase("stored amounts keep the lenient reading") {
            expectClose(Amount.parse("1.234,56"), 1234.56)
            expectClose(Amount.parse("25,50"), 25.5)
            expectClose(Amount.parse("25.50"), 25.5)
            expectClose(Amount.parse("50 €"), 50)
            expectNil(Amount.parse(""))
            expectNil(Amount.parse("abc"))
        },
        TestCase("status change in the future") {
            let result = try StatusHistory.apply(try base(), newStatus: "pausiert", changeDate: "2026-10-01")
            expectEqual(result["status"], "pausiert")
            expectEqual(result["statusHistory"], try json("""
                [{"status":"vollverdiener","startDate":"2024-01-01","endDate":"2025-06-01"},
                 {"status":"geringverdiener","startDate":"2025-06-01","endDate":"2026-10-01"},
                 {"status":"pausiert","startDate":"2026-10-01"}]
                """))
        },
        TestCase("status change backdated") {
            let result = try StatusHistory.apply(try base(), newStatus: "keinverdiener", changeDate: "2025-01-01")
            expectEqual(result["statusHistory"], try json("""
                [{"status":"vollverdiener","startDate":"2024-01-01","endDate":"2025-01-01"},{"status":"keinverdiener","startDate":"2025-01-01"}]
                """))
        },
        TestCase("status change at the start of the membership") {
            let result = try StatusHistory.apply(try base(), newStatus: "pausiert", changeDate: "2024-01-01")
            expectEqual(result["statusHistory"], try json(#"[{"status":"pausiert","startDate":"2024-01-01"}]"#))
        },
        TestCase("status change without a history") {
            let person = try json(#"{"status":"vollverdiener","memberSince":"2024-01-01","statusHistory":[]}"#)
            let result = try StatusHistory.apply(person, newStatus: "geringverdiener", changeDate: "2024-05-01")
            expectEqual(result["statusHistory"], try json("""
                [{"status":"vollverdiener","startDate":"2024-01-01","endDate":"2024-05-01"},{"status":"geringverdiener","startDate":"2024-05-01"}]
                """))
        },
        TestCase("a status change before the membership is refused") {
            expectThrows { _ = try StatusHistory.apply(try base(), newStatus: "pausiert", changeDate: "2023-12-31") }
        },
        TestCase("an approved status request ends the open first entry (members created by the server)") {
            let member = try json("""
                {"id":"p1","status":"vollverdiener","memberSince":"2025-01-01","originalMemberSince":"2025-01-01",
                 "payments":[],"standingOrders":[],"statusHistory":[{"status":"vollverdiener","startDate":"2025-01-01"}]}
                """)
            let approved = try RequestBookings.apply(member, request: try request("status", ["newStatus": "geringverdiener", "date": "2026-01-01"]), amount: 0)
            expectEqual(approved["status"], "geringverdiener")
            expectEqual(approved["statusHistory"], try json("""
                [{"status":"vollverdiener","startDate":"2025-01-01","endDate":"2026-01-01"},{"status":"geringverdiener","startDate":"2026-01-01"}]
                """))
        },
        TestCase("approving the same request again books nothing twice") {
            let person = try base()
            let payment = try request("payment", ["amount": "120.00", "date": "2026-10-01", "note": "Q4"])
            let once = try RequestBookings.apply(person, request: payment, amount: 120)
            // A second treasurer, a second device or a retry approves it again: the record already holds the booking
            let twice = try RequestBookings.apply(once, request: payment, amount: 120)
            expectEqual(ids(twice["payments"]), ["req_1760001"])
            expectClose(twice["totalPaid"]?.amount, 120)
            expectEqual(twice["payments"]?.arrayValue?.first?["description"], "Q4")
            let other = try request("payment", ["amount": "10", "date": "2026-10-02"], id: "1760002")
            expectEqual(ids(try RequestBookings.apply(twice, request: other, amount: 10)["payments"]).count, 2, "another request is another booking")

            let order = try request("standing_order", ["amount": "30.00", "date": "2026-11-01"])
            let orders = try RequestBookings.apply(try RequestBookings.apply(person, request: order, amount: 30), request: order, amount: 30)
            expectEqual(ids(orders["standingOrders"]), ["req_1760001"])
            expectEqual(orders["standingOrders"]?.arrayValue?.first?["note"], "Dauerauftrag (Genehmigt)")

            let expense = try request("expense", ["amount": "45.90", "date": "2026-10-02", "description": "Kaffee"])
            let expenses = RequestBookings.addingExpense([["id": 1, "amount": 5]], request: expense, amount: 45.9)
            expectEqual(expenses?.count, 2)
            expectEqual(expenses?.last?["issuer"], "Paula")
            expectNil(RequestBookings.addingExpense(expenses ?? [], request: expense, amount: 45.9), "already booked: nothing to save")

            // An approved status change is the treasurer's status change, also when it is applied twice
            let status = try request("status", ["newStatus": "pausiert", "date": "2026-10-01"])
            expectEqual(try RequestBookings.apply(try RequestBookings.apply(person, request: status, amount: 0), request: status, amount: 0),
                        try StatusHistory.apply(person, newStatus: "pausiert", changeDate: "2026-10-01"))
        },
        TestCase("an approval that lost against a rejection is taken back completely") {
            let paula = try json("""
                {"status":"vollverdiener","memberSince":"2025-01-01","payments":[{"id":"own","amount":50,"date":"2026-01-05"}],
                 "standingOrders":[{"id":"so","amount":25,"startDate":"2026-02-01"}],"statusHistory":[]}
                """)
            for booked in [try request("payment", ["amount": "120", "date": "2026-10-01"]), try request("standing_order", ["amount": "50", "date": "2026-11-01"])] {
                let undone = RequestBookings.removingBooking(try RequestBookings.apply(paula, request: booked, amount: 120), request: booked, before: paula)
                expectEqual(undone["payments"], paula["payments"], booked.type)
                expectEqual(undone["standingOrders"], paula["standingOrders"], booked.type)
            }
            let person = try base()
            let status = try request("status", ["newStatus": "pausiert", "date": "2026-10-01"])
            let restored = RequestBookings.removingBooking(try RequestBookings.apply(person, request: status, amount: 0), request: status, before: person)
            expectEqual(restored["status"], person["status"])
            expectEqual(restored["statusHistory"], person["statusHistory"])

            let expense = try request("expense", ["amount": "45.90", "date": "2026-10-02", "description": "Kaffee"])
            let other: JSONValue = ["id": 1717]
            expectEqual(RequestBookings.removingExpense(RequestBookings.addingExpense([other], request: expense, amount: 45.9) ?? [], request: expense), [other])
            expectNil(RequestBookings.removingExpense([other], request: expense), "nothing booked: nothing to save")
        },
        TestCase("a standing order ends in the future") {
            let result = StandingOrders.end(try personWithStandingOrder(), orderId: "so1", endDate: "2026-12-31", today: "2026-09-30")
            // The order stays with its end date, nothing is taken back
            expectEqual(ids(result["standingOrders"]), ["so1", "so2"])
            expectEqual(result["standingOrders"]?.arrayValue?.first?["endDate"], "2026-12-31")
            expectEqual(ids(result["payments"]).count, 5)
            expectClose(result["totalPaid"]?.amount, 270)
            // Ending today keeps it for today as well
            expectEqual(ids(StandingOrders.end(try personWithStandingOrder(), orderId: "so1", endDate: "2026-09-30", today: "2026-09-30")["standingOrders"]), ["so1", "so2"])
        },
        TestCase("a standing order ends retroactively") {
            let result = StandingOrders.end(try personWithStandingOrder(), orderId: "so1", endDate: "2026-08-03", today: "2026-09-30")
            // Ended in the past: the order is gone, its automatic payment after the end date is taken back
            expectEqual(ids(result["standingOrders"]), ["so2"])
            expectEqual(ids(result["payments"]), ["1700000000000", "auto_so1_2026-07-01", "auto_so1_2026-08-01", "auto_so2_2026-09-01"])
            expectClose(result["totalPaid"]?.amount, 220)
            expectEqual(result["name"], "Max")
            // An invalid date changes nothing
            expectEqual(StandingOrders.end(try personWithStandingOrder(), orderId: "so1", endDate: "", today: "2026-09-30"), try personWithStandingOrder())
        },
        TestCase("removing a standing order keeps its payments") {
            let result = StandingOrders.remove(try personWithStandingOrder(), orderId: "so1")
            expectEqual(ids(result["standingOrders"]), ["so2"])
            expectEqual(ids(result["payments"]).count, 5)
        },
        TestCase("receipt fields of all versions are read") {
            // current format: JSON array as text; bookings from older versions: plain name or comma list
            expectEqual(Receipts.parse(.string(#"["A-2026-05-30-1.jpg","A-2026-05-30-2.jpg"]"#)), ["A-2026-05-30-1.jpg", "A-2026-05-30-2.jpg"])
            expectEqual(Receipts.parse(.string("Angelina_Fott-2026-03-13-1.jpg")), ["Angelina_Fott-2026-03-13-1.jpg"])
            expectEqual(Receipts.parse(.string(" a.jpg, b.jpg ")), ["a.jpg", "b.jpg"])
            expectEqual(Receipts.parse(nil), [])
            expectEqual(Receipts.parse(.string("  ")), [])
            expectEqual(Receipts.parse(.string("[]")), [])
        },
        TestCase("people with legacy values are read") {
            let person = try decode(Person.self, """
                {"id":1717000000000,"name":"Anna","totalPaid":"1.234,50",
                 "payments":[{"id":1717,"amount":"50,00","date":"2024-02-01"},{"id":"auto_1_2024-03-01","amount":50,"date":"2024-03-01","isAuto":true}],
                 "_paidUntil":"2026-10-30T22:00:00.000Z","_statusMeta":{"text":"Alles in Ordnung"}}
                """)
            expectEqual(person.id, "1717000000000")
            expectClose(person.totalPaid, 1234.5)
            expectClose(person.payments.first?.amount, 50)
            expectEqual(person.payments.first?.id, "1717")
            expectEqual(person.statusMeta.text, "Alles in Ordnung")
            // local midnight of 31 October in UTC+2 must still be October
            expectEqual(Formats.paidUntilMonth(person.paidUntil), Formats.monthYear("2026-10"))
        }
    ]

    static func base() throws -> JSONValue {
        try json("""
            {"status":"vollverdiener","memberSince":"2024-01-01","originalMemberSince":"2024-01-01",
             "statusHistory":[{"status":"vollverdiener","startDate":"2024-01-01","endDate":"2025-06-01"},
                              {"status":"geringverdiener","startDate":"2025-06-01"}]}
            """)
    }

    static func personWithStandingOrder() throws -> JSONValue {
        try json("""
            {"name":"Max","totalPaid":250,
             "payments":[{"id":1700000000000,"amount":100,"date":"2026-05-02","description":"Bar"},
                         {"id":"auto_so1_2026-07-01","amount":50,"date":"2026-07-01","isAuto":true},
                         {"id":"auto_so1_2026-08-01","amount":50,"date":"2026-08-03","isAuto":true},
                         {"id":"auto_so1_2026-09-01","amount":50,"date":"2026-09-01","isAuto":true},
                         {"id":"auto_so2_2026-09-01","amount":20,"date":"2026-09-01","isAuto":true}],
             "standingOrders":[{"id":"so1","amount":50,"startDate":"2026-07-01","note":"Beitrag","lastAutoPayment":"2026-09-01"},
                               {"id":"so2","amount":20,"startDate":"2026-09-01","note":""}]}
            """)
    }

    static func request(_ type: String, _ data: [String: String], id: String = "1760001") throws -> FinanceRequest {
        let value: JSONValue = ["id": .string(id), "type": .string(type), "personName": "Paula", "data": .object(data.mapValues { .string($0) })]
        return try JSONDecoder().decode(FinanceRequest.self, from: JSONEncoder().encode(value))
    }

    static func ids(_ list: JSONValue?) -> [String] { (list?.arrayValue ?? []).compactMap { $0["id"]?.text } }
}
