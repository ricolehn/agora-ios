import Foundation

/// Event rules shared with the web app (assets/app.js) and Android (LogicTest.kt).
enum EventTests {
    static let all: [TestCase] = [
        TestCase("share links are the web app's addresses") {
            // Expected links were produced by the web app's slugify / itemSlug / encodeURIComponent (assets/app.js)
            let events = [
                try event(#"{"id":"a1","title":"Jugendfreizeit 2026","date":"2026-11-06"}"#),
                try event(#"{"id":"g1","title":"Gottesdienst","date":"2026-10-11"}"#),
                try event(#"{"id":"g2","title":"Gottesdienst","date":"2026-10-18"}"#),
                try event(#"{"id":"g3","title":"Gottesdienst","date":"2026-10-18"}"#),
                try event(#"{"id":"u1","title":"  Größer Gott – Lobpreis & Gebet! ","date":"2026-12-01"}"#),
                try event(#"{"id":"e1","title":"!!!","date":"2026-12-02"}"#),
                try event(#"{"id":"l1","title":"\#(String(repeating: "x", count: 90))","date":"2026-12-03"}"#)
            ]
            func link(_ index: Int) -> String { EventLinks.shareURL(baseURL: "https://agora.example/", event: events[index], among: events) }
            expectEqual(link(0), "https://agora.example/events/Jugendfreizeit_2026")
            // Repeated titles: the date tells them apart, on the same date the id
            expectEqual(link(1), "https://agora.example/events/Gottesdienst_2026-10-11")
            expectEqual(link(2), "https://agora.example/events/Gottesdienst~g2")
            expectEqual(link(3), "https://agora.example/events/Gottesdienst~g3")
            expectEqual(link(4), "https://agora.example/events/Gr%C3%B6%C3%9Fer_Gott_Lobpreis_Gebet")
            expectEqual(link(5), "https://agora.example/events/e1")
            expectEqual(link(6), "https://agora.example/events/" + String(repeating: "x", count: 80))
            // With the switch on the link carries the share key; off (or an old server) it is the members' address
            var shared = events[0]
            shared.isPublic = true
            shared.publicToken = "Oygrx2H59aHvWr7KkdIaaQ"
            expectEqual(EventLinks.shareURL(baseURL: "https://agora.example", event: shared, among: [shared]),
                        "https://agora.example/events/Jugendfreizeit_2026?share=Oygrx2H59aHvWr7KkdIaaQ")
            shared.isPublic = false
            expectEqual(EventLinks.shareURL(baseURL: "https://agora.example", event: shared, among: [shared]),
                        "https://agora.example/events/Jugendfreizeit_2026")
        },
        TestCase("slugs keep letters of every script and decompose nothing") {
            expectEqual(EventLinks.slugify("Café  am Abend"), "Café_am_Abend")
            // a decomposed é (e + combining accent) is composed first, like normalize('NFC')
            expectEqual(EventLinks.slugify("Cafe\u{301}"), "Café")
            expectEqual(EventLinks.slugify("Ελληνικά & 日本語"), "Ελληνικά_日本語")
            expectEqual(EventLinks.slugify("🎉"), "")
        },
        TestCase("sharing and guests from servers old and new") {
            // Before v3.2 there is no switch (nil: the sheet shows none), from v3.2 on its state and the link's key
            expectNil(try event(#"{"id":"e1","title":"Fest"}"#).isPublic)
            let shared = try event(#"{"id":"e1","title":"Fest","isPublic":true,"publicToken":"abc"}"#)
            expectEqual(shared.isPublic, true)
            expectEqual(shared.publicToken, "abc")
            let attendees = try decode(Attendees.self, """
                {"registered":[
                  {"id":"r1","userId":"u1","name":"Max","status":"registered"},
                  {"id":"g1","userId":"guest:g1","name":"Anna Gast","status":"registered","guest":true,"email":"anna@example.org","age":16},
                  {"id":"g2","userId":"guest:g2","name":"Ben Gast","status":"registered","guest":true}]}
                """)
            let member = attendees.registered[0], guest = attendees.registered[1], guestSeenByMember = attendees.registered[2]
            expect(!member.guest)
            expectEqual(member.pictureUserId, "u1")
            expect(guest.guest)
            expectEqual(guest.email, "anna@example.org")
            expectEqual(guest.age, 16)
            expectNil(guest.pictureUserId, "guests have no profile picture")
            // Members who may not edit the event get no contact details
            expectEqual(guestSeenByMember.email, "")
            expectNil(guestSeenByMember.age)
        },
        TestCase("the Termine list follows the web app's filter") {
            var me = User()
            me.uid = "me"
            me.groups = ["g1"]
            let today = "2026-09-28"
            // An event on 4 October with the given fields changed
            func shows(_ fields: String) throws -> Bool {
                var value: JSONValue = ["id": "e", "date": "2026-10-04", "eventType": "event"]
                for (key, field) in try json("{\(fields)}").objectValue ?? [:] { value[key] = field }
                let changed = try JSONDecoder().decode(AgoraEvent.self, from: JSONEncoder().encode(value))
                return EventRules.showsInTermine(changed, user: me, today: today)
            }
            expect(try shows(#""eventType":"termin""#))
            expect(try !shows(#""eventType":"termin","date":"2026-09-01""#), "past")
            expect(try shows(""))
            expect(try !shows(#""requiresRegistration":true"#))
            expect(try shows(#""requiresRegistration":true,"myRegistration":{"id":"r","status":"registered"}"#))
            expect(try !shows(#""isPinned":true"#))
            expect(try shows(#""isPinned":true,"duties":[{"id":"d","assignedUser":"me","status":"confirmed"}]"#))
            expect(try shows(#""isPinned":true,"duties":[{"id":"d","assignedGroup":"g1","status":"assigned"}]"#))
            // Registered highlights appear in Termine like in the web app
            expect(try shows(#""isPinned":true,"requiresRegistration":true,"myRegistration":{"id":"r","status":"registered"}"#))
        },
        TestCase("the church logo of the server: own logo or the default knot") {
            // Start of assets/church-logo.svg of the web app (v3.0+, light and dark fill)
            let knot = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-82 -82 2884 2884"><style>g{fill:#204E44}"#
                + ##"@media (prefers-color-scheme:dark){g{fill:#9ACBBE}}</style><g fill="#204E44"><path d="M0 0"/></g></svg>"##
            expect(ServerLogoRules.isDefaultLogo(knot))
            expect(!ServerLogoRules.isDefaultLogo(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle r="40" fill="#204E44"/></svg>"##))
            expect(!ServerLogoRules.isDefaultLogo(##"<?xml version="1.0"?><svg viewBox="-82 -82 2884 2884"><path fill="#123456" d="M0 0"/></svg>"##))
            // Only the <svg> element is drawn: an XML prolog or a comment before it would show up as text
            expectEqual(ServerLogoRules.svgElement(#"<?xml version="1.0"?><!-- logo --><svg viewBox="0 0 1 1"/>"#), #"<svg viewBox="0 0 1 1"/>"#)
            expectNil(ServerLogoRules.svgElement("<html>Not found</html>"))
        }
    ]

    static func event(_ text: String) throws -> AgoraEvent { try decode(AgoraEvent.self, text) }
}
