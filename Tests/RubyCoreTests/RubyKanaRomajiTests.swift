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
        // The particle は is wa; kanji have none, their readings being
        // furigana.
        #expect(beats(Self.student) == ["わ wa", "た ta", "し shi", "は wa", "で de", "す su"])
        let romaji = Self.student.kanaRomaji(in: .hepburn)
        #expect(romaji.map(\.range) == [0..<1, 1..<2, 2..<3, 3..<4, 6..<7, 7..<8])
        #expect(romaji.map(\.wordID) == ["watashi", "watashi", "watashi", "wa", "desu", "desu"])
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
        #expect(beats(content) == ["べ be", "を o", "べ be", "ま ma", "し shi", "た ta"])
        #expect(content.kanaRomaji(in: .hepburn).map(\.wordID) == ["food", "o", "eat", "eat", "eat", "eat"])
    }

    @Test func kanaInAWordReadAsAWhole() {
        let eat = RubyContent.content(for: [RubySegment("食べました", reading: "たべました")])
        #expect(beats(eat) == ["べ be", "ま ma", "し shi", "た ta"])
        // A っ before a kanji doubles what the kanji's reading starts with.
        let moving = RubyContent.content(for: [RubySegment("引っ越す", reading: "ひっこす")])
        #expect(beats(moving) == ["っ k", "す su"])
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
        #expect(beats(content) == ["こ ko", "ん n", "に ni", "ち chi", "は ha"])
    }

    @Test func rewrittenTextHasNone() {
        #expect(Self.student.transcribed(to: .hiragana).kanaRomaji(in: .hepburn).isEmpty)
        #expect(Self.student.withInlineReadings(in: .hiragana).kanaRomaji(in: .hepburn).isEmpty)
    }
}
