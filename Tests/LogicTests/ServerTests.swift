import Foundation

/// What the server answers (CALDERA): errors in the shape of API v2, of the old API, of a starting server and as plain
/// text, with the expected values of Android's ApiV2Test.
enum ServerTests {
    private static func parse(_ status: Int, _ body: String) -> APIError { APIError.parse(status: status, body: Data(body.utf8)) }

    static let all: [TestCase] = [
        TestCase("links in server content open only on the web, by e-mail or phone (Android 1.3.1)") {
            for link in ["https://agora.example/events", "http://example.org", "mailto:gemeinde@example.org", "tel:+4930123", "HTTPS://EXAMPLE.ORG"] {
                expect(LinkRules.opensFromText(URL(string: link)!), link)
            }
            for link in ["file:///etc/passwd", "intent://scan#Intent;end", "javascript:alert(1)", "shortcuts://run", "agora-other://x"] {
                expect(!LinkRules.opensFromText(URL(string: link)!), link)
            }
            for link in ["webcal://agora.example/feed.ics", "webcals://agora.example/feed.ics", "https://agora.example/feed.ics"] {
                expect(LinkRules.isCalendarSubscription(URL(string: link)!), link)
            }
            expect(!LinkRules.isCalendarSubscription(URL(string: "http://agora.example/feed.ics")!))
            expect(!LinkRules.isCalendarSubscription(URL(string: "file:///feed.ics")!))
        },
        TestCase("errors are read in the shape of API v2, of the old API, of a starting server and as plain text") {
            let v2 = parse(400, #"{"error":{"code":"invalid","message":"Der Betrag dieser Anfrage kann so nicht gebucht werden.","field":"details.amount"}}"#)
            expectEqual(v2.status, 400)
            expectEqual(v2.code, "invalid")
            expectEqual(v2.field, "details.amount")
            expectEqual(v2.message, "Der Betrag dieser Anfrage kann so nicht gebucht werden.")
            expect(!v2.isStarting)

            let old = parse(403, #"{"error":"Finance access rights required"}"#)
            expectEqual(old.message, "Finance access rights required")
            expectNil(old.code)
            expectNil(old.field)

            // A server that starts or upgrades its database: the old API says so, v2 by its code
            expect(parse(503, #"{"error":"The server is starting. Please try again in a moment.","starting":true}"#).isStarting)
            expect(parse(503, #"{"error":{"code":"unavailable","message":"The server is starting."}}"#).isStarting)
            expect(!parse(503, #"{"error":"App is in setup mode. Please configure first."}"#).isStarting)

            expectEqual(parse(401, "Unauthorized").message, "Unauthorized")
            // Express' own page of an unknown route: only its status, and no v2 code
            let page = parse(404, "<!DOCTYPE html><html><body><pre>Cannot GET /api/v2/members</pre></body></html>")
            expectEqual(page.message, "HTTP 404")
            expectNil(page.code)
            expectEqual(parse(500, #"{"unexpected":true}"#).message, "HTTP 500")
        },
        TestCase("what the app knows is said in its own German words, everything else as the server says it") {
            expectEqual(APIError.text(parse(503, #"{"error":"The server is starting. Please try again in a moment.","starting":true}"#)),
                        "Der Server startet gerade oder aktualisiert seine Datenbank. Bitte gleich noch einmal versuchen.")
            expectEqual(APIError.text(parse(429, #"{"error":{"code":"rate_limited","message":"Too many requests."}}"#)),
                        "Zu viele Anfragen auf einmal. Bitte einen Moment warten und erneut versuchen.")
            // The old API's bare conflict (a list or record changed meanwhile) is worded like v2's
            expectEqual(APIError.text(parse(409, #"{"error":"Conflict"}"#)),
                        "Das wurde inzwischen von jemand anderem geändert. Bitte neu laden und erneut versuchen.")
            expectEqual(APIError.text(parse(403, #"{"error":"Finanzverwaltungsrechte erforderlich"}"#)), "Finanzverwaltungsrechte erforderlich")
            expectEqual(APIError.text(CancellationError()), APIError.generic)
        }
    ]
}
