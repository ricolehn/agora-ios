import Foundation

// A small test runner for the app's logic. The app is a Swift Playgrounds package without a test target, so
// scripts/test-logic.sh compiles the UI-free sources (Core/Domain, Core/Models, Core/Support, the songbook logic)
// together with these files and runs them - on a Mac with Xcode as well as on Linux with a Swift toolchain.

#if !canImport(Darwin)
// Linux has no String(localized:); the app's German texts are their own localisation keys
extension String {
    init(localized key: String) { self = key }
}
#endif

struct TestCase {
    let name: String
    let body: () throws -> Void

    init(_ name: String, _ body: @escaping () throws -> Void) {
        self.name = name
        self.body = body
    }
}

enum TestKit {
    static var failures: [String] = []
    static var current = ""

    static func fail(_ message: String, file: StaticString, line: UInt) {
        failures.append("\(current)\n    \(file):\(line): \(message)")
    }

    /// Runs every case; returns the number of failed checks.
    static func run(_ suites: [(String, [TestCase])]) -> Int {
        var count = 0
        for (suite, cases) in suites {
            for test in cases {
                current = "\(suite) › \(test.name)"
                count += 1
                do {
                    try test.body()
                } catch {
                    failures.append("\(current)\n    unexpected error: \(error)")
                }
            }
        }
        if failures.isEmpty {
            print("✓ \(count) tests passed")
        } else {
            print(failures.map { "✗ \($0)" }.joined(separator: "\n"))
            print("\(failures.count) failed check(s) in \(count) tests")
        }
        return failures.count
    }
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !condition { TestKit.fail(message().isEmpty ? "expected true" : message(), file: file, line: line) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "",
                               file: StaticString = #fileID, line: UInt = #line) {
    if actual != expected { TestKit.fail("\(message()) expected \(expected), got \(actual)".trimmingCharacters(in: .whitespaces), file: file, line: line) }
}

func expectNil<T>(_ value: T?, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if let value { TestKit.fail("\(message()) expected nil, got \(value)".trimmingCharacters(in: .whitespaces), file: file, line: line) }
}

func expectClose(_ actual: Double?, _ expected: Double, _ message: @autoclosure () -> String = "",
                 file: StaticString = #fileID, line: UInt = #line) {
    guard let actual, abs(actual - expected) < 0.0001 else {
        TestKit.fail("\(message()) expected \(expected), got \(actual.map(String.init(describing:)) ?? "nil")".trimmingCharacters(in: .whitespaces),
                     file: file, line: line)
        return
    }
}

func expectThrows(_ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        TestKit.fail(message().isEmpty ? "expected an error" : message(), file: file, line: line)
    } catch {}
}

/// A model decoded from JSON text, the way the app reads server answers.
func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(text.utf8))
}

func json(_ text: String) throws -> JSONValue { try decode(JSONValue.self, text) }
