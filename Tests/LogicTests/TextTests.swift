import Foundation

/// AI answers and the songbook (logic ported from the web's songbook.js, like Android's SongbookLogicTest.kt).
enum TextTests {
    static let all: [TestCase] = [
        TestCase("reasoning blocks are split from the answer") {
            let done = AiText.splitThinking("<think>plan the answer</think>Hallo **Welt**")
            expectEqual(done.visible, "Hallo **Welt**")
            expectEqual(done.thinking, "plan the answer")
            let streaming = AiText.splitThinking("<think>still thinking")
            expectEqual(streaming.visible, "")
            expectEqual(streaming.thinking, "still thinking")
        },
        TestCase("chords are recognised, words are not") {
            for chord in ["G", "F#m7", "Bbmaj7", "D/F#", "Csus4", "E7(b9)", "Am/G", "H7", "C°", "Gadd9"] {
                expect(SongbookLogic.parseChord(chord) != nil, chord)
            }
            for word in ["Bridge", "Chorus", "End", "N.C.", "", "X"] { expectNil(SongbookLogic.parseChord(word), word) }
            let chord = SongbookLogic.parseChord("F#m7/C#")
            expectEqual(chord?.root, "F")
            expectEqual(chord?.accidental, "#")
            expectEqual(chord?.quality, "m7")
            expectEqual(chord?.bass?.root, "C")
        },
        TestCase("transposing keeps quality and bass and spells by key") {
            expectEqual(SongbookLogic.transposeChord("G", steps: 2), "A")
            expectEqual(SongbookLogic.transposeChord("Gm7/D", steps: 2), "Am7/E")
            expectEqual(SongbookLogic.transposeChord("G", steps: 0), "G")
            expectEqual(SongbookLogic.transposeChord("Bridge", steps: 3), "Bridge")
            // F major is written with flats
            let song = "[F]Amazing [Bb]grace"
            let flats = SongbookLogic.spelling(content: song, declaredKey: "F", steps: 5)
            expectEqual(SongbookLogic.transposeChord("F", steps: 5, spelling: flats), "Bb")
            expectEqual(SongbookLogic.transposeChord("Bb", steps: 5, spelling: flats), "Eb")
            // German notation keeps H and writes Bb as B
            let german = "[H]Großer [E]Gott"
            expectEqual(SongbookLogic.transposeChord("H", steps: 1, spelling: SongbookLogic.spelling(content: german, declaredKey: "H", steps: 1)), "C")
            expectEqual(SongbookLogic.transposeChord("B", steps: 1, spelling: SongbookLogic.spelling(content: german, declaredKey: "", steps: 1)), "H")
        },
        TestCase("transposed key and steps") {
            expectEqual(SongbookLogic.transposedKey("G", content: "[G]Amazing grace", steps: 2), "A")
            expectEqual(SongbookLogic.transposedKey("", content: "[G]x", steps: 2), "")
            expectEqual(SongbookLogic.step(5, by: 1), -6)
            expectEqual(SongbookLogic.step(-6, by: -1), 5)
            expectEqual(SongbookLogic.step(0, by: 1), 1)
        },
        TestCase("a song becomes sections, notes, gaps and chord lines") {
            let lines = SongbookLogic.parse("# Verse 1\n[G]Amazing [D/F#]grace\n\n\n[Bridge]\n{capo: 2}\n{c: Chorus}\n{soc}\n> twice\n[G] [D]\nOnly text")
            expectEqual(lines.count, 9)
            guard lines.count == 9 else { return }
            expectEqual(lines[0], .section(text: "Verse 1", label: nil))
            expectEqual(lines[1], .chords([[SongSegment(chord: "G", text: "Amazing ")], [SongSegment(chord: "D/F#", text: "grace")]]))
            expectEqual(lines[2], .gap)
            expectEqual(lines[3], .section(text: "Bridge", label: nil))
            expectEqual(lines[4], .section(text: "Chorus", label: nil))
            expectEqual(lines[5], .section(text: "", label: "chorus"))
            expectEqual(lines[6], .note("twice"))
            if case .chords(let words) = lines[7] { expect(SongbookLogic.chordsOnly(words)) } else { expect(false, "chord line expected") }
            expectEqual(lines[8], .text("Only text"))
        },
        TestCase("chords can be hidden and transposed while parsing") {
            let song = "[G]Amazing [D]grace\n[G] [D]"
            expectEqual(SongbookLogic.parse(song, chords: false), [.text("Amazing grace")])
            guard case .chords(let words) = SongbookLogic.parse(song, steps: 2).first else { return expect(false, "chord line expected") }
            expectEqual(words[0][0].chord, "A")
            expectEqual(words[1][0].chord, "E")
        },
        TestCase("a word that continues across a chord stays one word") {
            guard case .chords(let words) = SongbookLogic.parse("Ama[G]zing grace").first else { return expect(false, "chord line expected") }
            expectEqual(words[0], [SongSegment(chord: nil, text: "Ama"), SongSegment(chord: "G", text: "zing ")])
            expectEqual(words[1], [SongSegment(chord: nil, text: "grace")])
        },
        TestCase("search ignores case, accents and chords") {
            var song = Song()
            song.title = "Großer Gott"
            song.artist = "Ignaz Franz"
            song.ccli = "123"
            song.content = "# Refrain\n[G]Wir loben [D]dich"
            let text = SongbookLogic.searchText(song)
            expect(text.contains("wir loben dich"), text)
            expect(text.contains("123"), text)
            expect(!text.contains("[g]"), text)
            expect(!text.contains("refrain"), text)
            expectEqual(SongbookLogic.normalizeSearch("Crème  Brûlée"), "creme brulee")
        }
    ]
}
