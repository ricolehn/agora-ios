import Foundation

@main
enum LogicTests {
    static func main() {
        let failed = TestKit.run([
            ("Finances", FinanceTests.all),
            ("Events", EventTests.all),
            ("Texts and songbook", TextTests.all),
            ("Server answers", ServerTests.all)
        ])
        exit(failed == 0 ? 0 : 1)
    }
}
