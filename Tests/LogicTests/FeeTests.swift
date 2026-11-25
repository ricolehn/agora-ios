import Foundation

/// The fees over time and the fresh start of the fee accounts (CALDERA), with the expected values of Android's
/// FeeLogicTest. The server sends the fields with a leading underscore, like here.
enum FeeTests {
    private static let day = "2027-01-01"

    private static func person(_ fields: String) throws -> Person { try decode(Person.self, "{\(fields)}") }

    static let all: [TestCase] = [
        TestCase("the server's fresh start and monthly fee are read, and kept by the on-device cache") {
            let read = try person(#""id":"a","status":"vollverdiener","_feeReset":"2027-01-01","_feeCarriedOver":25,"_feeWrittenOff":"75.50","_monthlyFee":60"#)
            expectEqual(read.feeReset, day)
            expectClose(read.feeCarriedOver, 25)
            expectClose(read.feeWrittenOff, 75.5)
            expectClose(read.monthlyFee, 60)
            let cached = try JSONDecoder().decode(Person.self, from: JSONEncoder().encode(read))
            expectEqual(cached, read)
            // Older servers: none of it
            let old = try person(#""id":"b","status":"vollverdiener","_feeReset":null"#)
            expectNil(old.feeReset)
            expectNil(old.monthlyFee)
        },
        TestCase("the member card names a fresh start as a notice - from its day on, for 60 days") {
            expect(FeeRules.isNews("2026-11-01", today: "2026-11-01"), "on its day")
            expect(FeeRules.isNews("2026-11-01", today: "2026-12-30"), "day 59")
            expect(!FeeRules.isNews("2026-11-01", today: "2026-12-31"), "after 60 days it is old news")
            expect(!FeeRules.isNews("2026-11-01", today: "2027-06-01"))
            // the server sends the day once it has come: a device whose clock is behind still shows it
            expect(FeeRules.isNews("2026-11-01", today: "2026-10-31"))
            for value in [nil, "", "nonsense", "2026-11", "2026-02-30"] as [String?] {
                expect(!FeeRules.isNews(value, today: "2026-11-01"), String(describing: value))
            }
        },
        TestCase("a payment dated before the fresh start first pays off what was dropped then") {
            let behind = try person(#""_feeReset":"2027-01-01","_feeWrittenOff":300"#)
            expectClose(FeeRules.droppedFeesBefore(behind, paymentDay: "2026-12-20"), 300)
            expectClose(FeeRules.droppedFeesBefore(behind, paymentDay: day), 0, "from the day on a payment is credit")
            expectClose(FeeRules.droppedFeesBefore(try person(#""_feeReset":"2027-01-01","_feeCarriedOver":40"#), paymentDay: "2026-12-20"), 0,
                        "nothing was dropped")
            expectClose(FeeRules.droppedFeesBefore(try person(#""_feeWrittenOff":300"#), paymentDay: "2026-12-20"), 0, "no fresh start")
            expectClose(FeeRules.droppedFeesBefore(behind, paymentDay: ""), 0)
            expectClose(FeeRules.droppedFeesBefore(behind, paymentDay: nil), 0)
            expectClose(FeeRules.droppedFeesBefore(nil, paymentDay: "2026-12-20"), 0)
        },
        TestCase("what happened on the day of the fresh start") {
            expectEqual(FeeRules.resetOutcome(try person(#""_feeReset":"2027-01-01","_feeCarriedOver":25"#)), .carriedOver)
            expectEqual(FeeRules.resetOutcome(try person(#""_feeReset":"2027-01-01","_feeWrittenOff":75"#)), .dropped)
            expectEqual(FeeRules.resetOutcome(try person(#""_feeReset":"2027-01-01""#)), .even)
        },
        TestCase("the history marks the fresh start, the time before it is settled") {
            let fields = #""status":"vollverdiener","memberSince":"2025-03-01","#
                + #""statusHistory":[{"status":"geringverdiener","startDate":"2025-03-01","endDate":"2026-06-01"}],"#
                + #""payments":[{"id":1,"amount":50,"date":"2026-12-20"},{"id":2,"amount":60,"date":"2027-01-01"},{"id":3,"amount":70,"date":"2027-02-01"}]"#
            let lines = TimelineEntry.build(for: try person(fields + #","_feeReset":"2027-01-01""#))
            expectEqual(lines.map(\.date), ["2027-02-01", day, day, "2026-12-20", "2026-06-01", "2025-03-01"])
            // on its day the fresh start comes below that day's entries: they belong to the new account
            expectEqual(lines[1].kind, .payment(amount: 60, note: ""))
            expect(lines[2].isFreshStart)
            expectEqual(lines.map(\.settled), [false, false, false, true, true, true])
            // without a fresh start: the history as before
            let plain = TimelineEntry.build(for: try person(fields))
            expect(plain.allSatisfy { !$0.isFreshStart && !$0.settled })
            expectEqual(plain.count, 5)
            // nothing booked: nothing to mark either
            expect(TimelineEntry.build(for: try person(#""_feeReset":"2027-01-01""#)).isEmpty)
        },
        TestCase("the fee of the month comes from the server, older servers from the fee settings") {
            let settings = FeeSettings(rates: ["vollverdiener": 50, "geringverdiener": 25])
            expectClose(try person(#""status":"vollverdiener","_monthlyFee":60"#).monthlyFee(settings), 60)
            expectClose(try person(#""status":"vollverdiener","_monthlyFee":0"#).monthlyFee(settings), 0)
            expectClose(try person(#""status":"vollverdiener","_currentStatus":"geringverdiener""#).monthlyFee(settings), 25)
        }
    ]
}
