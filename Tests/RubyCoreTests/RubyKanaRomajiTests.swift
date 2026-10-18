import RubyCore
import RubyTransliteration
import Testing

/// Romaji under each kana, a beat at a time, for learners still learning
/// kana.
@Suite struct RubyKanaRomajiTests {
    /// Each beat of `content`'s kana, as written and in romaji.
    private func beats(_ content: RubyContent, in system: RubyRomanization = .hepburn) -> [String] {
        content.kanaRomaji(in: system).map { "\($0.kana) \($0.text)" }
    }

    /// わたしは学生です。, as an app gives it.
    private static let student = RubyContent.content(for: [
        RubySegment("わたし", wordID: "watashi"),
        RubySegment("は", word: .init(attachesToPrevious: true), wordID: "wa"),
        RubySegment("学生", reading: "がくせい", word: .init(attachesToPrevious: false), wordID: "gakusei"),
        RubySegment("です", word: .init(attachesToPrevious: true), wordID: "desu"),
        RubySegment("。", source: .dictionary),
    ])

    @Test func eachKanaHasItsBeat() {
        // The particle は is wa, and 学生's reading is one, under both kanji.
        #expect(beats(Self.student) == ["わ wa", "た ta", "し shi", "は wa", "がくせい gakusei", "で de", "す su"])
        let romaji = Self.student.kanaRomaji(in: .hepburn)
        #expect(romaji.map(\.range) == [0..<1, 1..<2, 2..<3, 3..<4, 4..<6, 6..<7, 7..<8])
        #expect(romaji.map(\.wordID) == ["watashi", "watashi", "watashi", "wa", "gakusei", "desu", "desu"])
        #expect(romaji.map(\.isReading) == [false, false, false, false, true, false, false])
    }

    /// 食べ物を食べました, with each reading over its own kanji.
    @Test func kanaInWordsGivenInPieces() {
        let content = RubyContent.content(for: [
            RubySegment("食", reading: "た", wordID: "food"),
            RubySegment("べ", wordID: "food"),
            RubySegment("物", reading: "もの", wordID: "food"),
            RubySegment("を", word: .init(attachesToPrevious: true), wordID: "o"),
            RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "eat"),
            RubySegment("べました", wordID: "eat"),
        ])
        #expect(beats(content) == ["た ta", "べ be", "もの mono", "を o", "た ta", "べ be", "ま ma", "し shi", "た ta"])
        #expect(content.kanaRomaji(in: .hepburn).map(\.wordID) == ["food", "food", "food", "o", "eat", "eat", "eat", "eat", "eat"])
    }

    @Test func kanaInAWordReadAsAWhole() {
        let eat = RubyContent.content(for: [RubySegment("食べました", reading: "たべました")])
        #expect(beats(eat) == ["た ta", "べ be", "ま ma", "し shi", "た ta"])
        // A っ before a kanji doubles what the kanji's reading starts with.
        let moving = RubyContent.content(for: [RubySegment("引っ越す", reading: "ひっこす")])
        #expect(beats(moving) == ["ひ hi", "っ k", "こ ko", "す su"])
    }

    /// Kana with a small one after them, っ, ん and long vowels are a beat
    /// each, as the system writes them.
    @Test func beatsOfMoreThanOneKana() {
        let content = RubyContent.content(for: [
            RubySegment("きょう"),
            RubySegment("、", source: .dictionary),
            RubySegment("コーヒー"),
            RubySegment("を", word: .init(partOfSpeech: .particle)),
            RubySegment("のん"),
            RubySegment("で"),
            RubySegment("いっ"),
            RubySegment("た"),
        ])
        #expect(beats(content) == [
            "きょ kyo", "う o", "コ ko", "ー o", "ヒ hi", "ー i", "を o", "の no", "ん n", "で de", "い i", "っ t", "た ta",
        ])
        #expect(beats(content, in: .wapuro) == [
            "きょ kyo", "う u", "コ ko", "ー -", "ヒ hi", "ー -", "を wo", "の no", "ん n", "で de", "い i", "っ t", "た ta",
        ])
    }

    @Test func aReadingOverKanaIsHowTheyreRead() {
        #expect(beats(.content(for: "{は|わ}", analyzer: nil)) == ["は wa"])
    }

    @Test func kanaOutsideWordsAreReadAsWritten() {
        // Without an analyzer, only the markup's word is known.
        let content = RubyContent.content(for: "こんにちは、{世界|せかい}。", analyzer: nil)
        #expect(beats(content) == ["こ ko", "ん n", "に ni", "ち chi", "は ha", "せかい sekai"])
    }

    /// A reading over kanji is kana too, so it has its romaji under its
    /// kanji: the whole reading, as romaji write a word.
    @Test func readingsHaveTheirRomajiUnderTheirKanji() {
        let big = RubyContent.content(for: [
            RubySegment("大", reading: "おお", wordID: "ookii"),
            RubySegment("きい", wordID: "ookii"),
        ])
        #expect(beats(big) == ["おお ō", "き ki", "い i"])
        #expect(beats(big, in: .wapuro) == ["おお oo", "き ki", "い i"])
        let romaji = big.kanaRomaji(in: .hepburn)
        #expect(romaji.map(\.range) == [0..<1, 1..<2, 2..<3])
        #expect(romaji.map(\.wordID) == ["ookii", "ookii", "ookii"])
        // Each beat of the reading as written, so it's known once each is.
        #expect(romaji.map(\.beats) == [["お", "お"], ["き"], ["い"]])
        // A long vowel as the system writes a word: ō in Hepburn, and
        // spelled out in wāpuro, as the kana under it would be.
        let tokyo = RubyContent.content(for: [RubySegment("東京", reading: "とうきょう")])
        #expect(beats(tokyo) == ["とうきょう tōkyō"])
        #expect(beats(tokyo, in: .wapuro) == ["とうきょう toukyou"])
        #expect(tokyo.kanaRomaji(in: .hepburn).map(\.beats) == [["と", "う", "きょ", "う"]])
    }

    @Test func aReadingIsSaidAsItsWordIs() {
        // Names are capitalized, as romaji write them.
        let name = RubyContent.content(for: [RubySegment("田中", reading: "たなか", word: .init(isProperNoun: true))])
        #expect(beats(name) == ["たなか Tanaka"])
        // A reading ending in っ doubles what comes next.
        let school = RubyContent.content(for: [
            RubySegment("学", reading: "がっ", wordID: "gakkou"),
            RubySegment("校", reading: "こう", wordID: "gakkou"),
        ])
        #expect(beats(school, in: .wapuro) == ["がっ gak", "こう kou"])
        // Readings over digits have them too.
        let three = RubyContent.content(for: [RubySegment("3", reading: "さん", wordID: "sanji"), RubySegment("じ", wordID: "sanji")])
        #expect(beats(three) == ["さん san", "じ ji"])
    }

    @Test func rewrittenTextHasNone() {
        #expect(Self.student.transcribed(to: .hiragana).kanaRomaji(in: .hepburn).isEmpty)
        #expect(Self.student.withInlineReadings(in: .hiragana).kanaRomaji(in: .hepburn).isEmpty)
    }
}
