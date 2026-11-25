import Foundation

/// One AI reply as the server streams it: thoughts, text and – from CALDERA on – the lookups the server makes for the
/// AI, with the expected values of Android's AiReplyTest (which ports the web's tests/frontend.test.js).
enum AiTests {
    private static func chunks(_ line: String) throws -> [AiChunk] { AiChunk.of(try decode([String: JSONValue].self, line)) }
    private static func live(_ text: String) -> String { AiReplyText.liveTitle(text, settled: false) }

    static let all: [TestCase] = [
        TestCase("the stream's lines become text, thoughts, lookups and what they found") {
            expectEqual(try chunks(#"{"content":"Hallo"}"#), [.content("Hallo")])
            expectEqual(try chunks(#"{"reasoning":"Hm"}"#), [.reasoning("Hm")])
            expectEqual(try chunks(#"{"lookup":{"id":1,"tool":"money","step":"Finding the expenses for flowers","from":"2019","to":"2024","about":"Blumen"}}"#),
                        [.lookup(AiLookup(id: 1, tool: "money", step: "Finding the expenses for flowers", from: "2019", to: "2024", about: "Blumen"))])
            expectEqual(try chunks(#"{"lookup":{"id":2,"tool":"events"}}"#), [.lookup(AiLookup(id: 2, tool: "events"))])
            expectEqual(try chunks(#"{"lookupDone":{"id":1,"count":12,"unit":"entries","eur":345.5,"cut":true}}"#),
                        [.lookupDone(AiLookupDone(id: 1, count: 12, unit: "entries", eur: 345.5, cut: true))])
            expectEqual(try chunks(#"{"lookupDone":{"id":3,"error":"forbidden"}}"#), [.lookupDone(AiLookupDone(id: 3, error: "forbidden"))])
            // Whatever else may come one day is left alone
            expectEqual(try chunks(#"{"somethingNew":{"a":1}}"#), [])
        },
        TestCase("text written before a lookup is a note on the way - the answer is what comes after the last lookup") {
            var work = AiReplyWork()
            work.add(.reasoning("I should look "))
            work.add(.reasoning("this up."))
            work.add(.content("<think>maybe flowers</think>Let me check the expenses."))
            let lookup = AiLookup(id: 1, tool: "expenses", from: "2019", to: "2024")
            work.add(.lookup(lookup))
            expectEqual(work.lookups, 1)
            expectEqual(work.content, "")
            expectEqual(AiReplyText.liveLabel(steps: work.steps, content: work.content), .lookup(lookup), "the AI is on the lookup")
            let found = AiLookupDone(id: 1, count: 4, unit: "entries", eur: 120)
            work.add(.lookupDone(found))
            expectEqual(AiReplyText.liveLabel(steps: work.steps, content: work.content), .lookup(lookup), "still on it while it reads")
            work.add(.content("You spent **120 €** on flowers."))
            expectEqual(work.content, "You spent **120 €** on flowers.")
            expectEqual(work.steps, [.thought("I should look this up."), .thought("maybe flowers"), .note("Let me check the expenses."),
                                     .lookup(lookup, done: found)])
        },
        TestCase("what a lookup found goes to that lookup, also when two ran one after the other") {
            var work = AiReplyWork()
            work.add(.lookup(AiLookup(id: 1, tool: "members")))
            work.add(.lookup(AiLookup(id: 2, tool: "payments")))
            work.add(.lookupDone(AiLookupDone(id: 1, count: 3, unit: "members")))
            work.add(.lookupDone(AiLookupDone(id: 2, error: "failed")))
            expectEqual(work.steps, [.lookup(AiLookup(id: 1, tool: "members"), done: AiLookupDone(id: 1, count: 3, unit: "members")),
                                     .lookup(AiLookup(id: 2, tool: "payments"), done: AiLookupDone(id: 2, error: "failed"))])
            expectEqual(work.lookups, 2)
        },
        TestCase("a reply without lookups is as before - thoughts apart, the text the answer") {
            var work = AiReplyWork()
            work.add(.reasoning("Easy."))
            work.add(.content("42"))
            expectEqual(work.steps, [.thought("Easy.")])
            expectEqual(work.content, "42")
            expectEqual(work.lookups, 0)
        },
        TestCase("the live title - the newest heading of the thoughts, else the newest sentence, without filler words") {
            expectEqual(AiReplyText.liveTitle("**Checking the expenses**\n\nI look at December.\n\n**Calculating monthly expenses**\n\nThe totals per"),
                        "Calculating monthly expenses")
            expectEqual(AiReplyText.liveTitle("## Finding Nick in the members\nHe joined"), "Finding Nick in the members")
            expectEqual(AiReplyText.liveTitle("Okay, the user asks about Christmas. Let me check the December expenses."), "Let me check the December expenses")
            expectEqual(AiReplyText.liveTitle("Gut, jetzt rechne ich die Monatsausgaben zusammen."), "Jetzt rechne ich die Monatsausgaben zusammen")
            expectEqual(AiReplyText.liveTitle("- Check the expenses of December\n- Check the totals of every year"), "Check the totals of every year")
            expectEqual(AiReplyText.liveTitle("   \n "), "")
            // A sentence that says nothing gives no title: the one before it stays
            expectEqual(AiReplyText.liveTitle("I check the books first. Hmm. Yes."), "I check the books first")
            let long = AiReplyText.liveTitle("Now I compare " + String(repeating: "every single payment of every member ", count: 4) + "since 2019.")
            expect(long.count <= 72 && long.hasSuffix("…"), long)
            expect(AiReplyText.liveTitle("Now I compare every single payment of every member since 2019.", max: 30).count <= 30)
        },
        TestCase("while the thoughts come in, only what is finished gives a title - it never writes itself letter by letter") {
            expectEqual(live("**Und"), "")
            expectEqual(live("**Understanding the question**"), "")
            expectEqual(live("**Understanding the question**\n"), "Understanding the question")
            expectEqual(live("**Understanding the question**\n\nThe person wants to know what the services cost. I should"), "Understanding the question")
            expectEqual(live("**Checking the expenses**\n\nI look at December.\n\n**Calculating monthly"), "Checking the expenses")
            expectEqual(live("## Finding Nick in the mem"), "")
            // Bold words at the start of a line are no heading
            expectEqual(live("I look at the members first.\n**Important** is the"), "I look at the members first")
            // A sentence counts when the next one has begun
            expectEqual(live("I need the yearly"), "")
            expectEqual(live("I need the yearly totals."), "")
            expectEqual(live("I need the yearly totals. Then I"), "I need the yearly totals")
            expectEqual(live("I need the yearly totals. Then I compare them with the budget"), "I need the yearly totals")
            expectEqual(live("I need the yearly totals. Then I compare them with the budget. Af"), "Then I compare them with the budget")
            expectEqual(live("I need the yearly totals.\n"), "I need the yearly totals")
            // A full stop inside a number or an abbreviation ends nothing
            expectEqual(live("The candles cost 3."), "")
            expectEqual(live("The candles cost 3.50 euros, e.g. the red ones. Next"), "The candles cost 3.50 euros, e.g. the red ones")
            // The same text as it grows: the title only changes from one finished title to the next
            let thought = "Okay, the user asks about Christmas. Let me check the December expenses. Then I add them up per year."
            var titles: [String] = []
            for length in 1...thought.count {
                let title = live(String(thought.prefix(length)))
                if !titles.contains(title) { titles.append(title) }
            }
            expectEqual(titles, ["", "The user asks about Christmas", "Let me check the December expenses"])
            expectEqual(AiReplyText.liveTitle(thought), "Then I add them up per year", "complete, the last sentence counts as well")
        },
        TestCase("spaces of every kind are spaces, the no-break ones too - as the web's") {
            expectEqual(live("I need the yearly totals.\u{00A0}Then I"), "I need the yearly totals")
            expectEqual(live("Ich brauche die Summen pro Jahr.\u{202F}Dann"), "Ich brauche die Summen pro Jahr")
            expectEqual(AiReplyText.lookupStep(AiLookup(id: 1, tool: "members", step: "finding\u{00A0}Nick\u{3000}in \u{2009}the\tmembers")),
                        "Finding Nick in the members")
        },
        TestCase("the line names the lookup it is on, then the newest thought once it has a finished title") {
            expectEqual(AiReplyText.lookupStep(AiLookup(id: 2, tool: "expenses", step: "  finding   Nick in the members ")), "Finding Nick in the members")
            expectNil(AiReplyText.lookupStep(AiLookup(id: 2, tool: "expenses", from: "2019")), "no words of the model: the screen names what it reads")

            var work = AiReplyWork()
            func label(_ inline: String) -> AiLiveLabel? { AiReplyText.liveLabel(steps: work.steps, content: work.content, inlineThinking: inline) }
            expectNil(label(""))
            work.add(.reasoning("**Reading the question**"))
            expectNil(label(""), "the heading may still grow")
            work.add(.reasoning("\n\nThe person asks"))
            expectEqual(label(""), .thought("Reading the question"))
            let lookup = AiLookup(id: 2, tool: "expenses", step: "Suche die Weihnachtskosten", from: "2019", to: "2024", about: "Christmas")
            work.add(.lookup(lookup))
            expectEqual(label(""), .lookup(lookup))
            work.add(.lookupDone(AiLookupDone(id: 2, count: 3, unit: "entries")))
            expectEqual(label(""), .lookup(lookup))
            work.add(.reasoning("Jetzt rechne ich die Summe pro Jahr aus."))
            expectEqual(label(""), .lookup(lookup), "the lookup stays until the new thought has a title")
            work.add(.reasoning(" Dann vergleiche"))
            expectEqual(label(""), .thought("Jetzt rechne ich die Summe pro Jahr aus"))
            expectEqual(label("Prüfe die Mitglieder. Dann"), .thought("Prüfe die Mitglieder"))
            expectEqual(label("Prüfe die Mitgl"), .thought("Jetzt rechne ich die Summe pro Jahr aus"), "a <think> block without a finished sentence yet")

            // Thoughts that are over count in full: a lookup or the text of the round follows them
            var over = AiReplyWork()
            over.add(.reasoning("**Reading the question**"))
            over.add(.content("Moment."))
            expectEqual(AiReplyText.liveLabel(steps: over.steps, content: over.content), .thought("Reading the question"))
            over.add(.lookup(AiLookup(id: 1, tool: "members")))
            over.add(.reasoning("Nick ist seit 2019 dabei."))
            over.add(.content("Nick"))
            expectEqual(AiReplyText.liveLabel(steps: over.steps, content: over.content), .thought("Nick ist seit 2019 dabei"))
        },
        TestCase("lookups are named in German like Android and the web") {
            expectEqual(AiReplyText.lookupTitle(AiLookup(id: 1, tool: "expenses", from: "2019", to: "2024", about: "Blumen")),
                        "Schlägt Ausgaben 2019–2024 „Blumen“ nach")
            expectEqual(AiReplyText.lookupWhat(AiLookup(id: 1, tool: "payments", from: "2020")), "Zahlungen seit 2020")
            expectEqual(AiReplyText.lookupWhat(AiLookup(id: 1, tool: "something-new", to: "2021")), "Daten bis 2021")
            expectEqual(AiReplyText.lookupWhat(AiLookup(id: 1, tool: "events", from: "2025", to: "2025")), "Termine 2025")
            let money = { (value: Double) in String(format: "%.2f €", value) }
            expectEqual(AiReplyText.lookupFound(AiLookupDone(id: 1, count: 12, unit: "entries", eur: 345.5, cut: true), money: money), "12 Einträge · 345.50 € · gekürzt")
            expectEqual(AiReplyText.lookupFound(AiLookupDone(id: 1, count: 1, unit: "members"), money: money), "1 Mitglied")
            expectEqual(AiReplyText.lookupFound(AiLookupDone(id: 1, error: "forbidden"), money: money), "nicht erlaubt")
            expectEqual(AiReplyText.lookupFound(AiLookupDone(id: 1, error: "failed"), money: money), "fehlgeschlagen")
            expectNil(AiReplyText.lookupFound(nil, money: money))
            expectEqual(AiReplyText.doneTitle(lookups: 2), "Nachgedacht · 2× nachgeschlagen")
            expectEqual(AiReplyText.doneTitle(lookups: 0), "Nachgedacht")
        }
    ]
}
