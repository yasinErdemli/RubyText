import RubyCore
import Testing

/// Content rewritten in another script or with inline readings, and where
/// its words moved.
@Suite struct RubyTranscriptionTests {
    private static let sentence = "今日は東京へ行きたい。"

    /// The rewritten text of each word, in order.
    private func words(of content: RubyContent) -> [String] {
        content.words.map { RubyReadingUnits.substring(of: content.string, utf16Range: $0.range) }
    }

    @Test func hiraganaWordsMove() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .hiragana)
        #expect(content.string == "きょうはとうきょうへいきたい。")
        #expect(words(of: content) == ["きょう", "は", "とうきょう", "へ", "いき", "たい"])
        #expect(content.words.allSatisfy { $0.furigana.isEmpty })
        // Romaji stay, to show over the kana.
        #expect(content.romajiWords.map(\.text) == ["kyō", "wa", "tōkyō", "e", "ikitai"])
    }

    @Test func katakana() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .katakana)
        #expect(content.string == "キョウハトウキョウヘイキタイ。")
        #expect(words(of: content).first == "キョウ")
    }

    @Test func romajiWordsMove() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .romaji)
        #expect(content.string == "kyō wa tōkyō e ikitai.")
        // 行き and たい share the romaji word ikitai, divided between them.
        #expect(words(of: content) == ["kyō", "wa", "tōkyō", "e", "iki", "tai"])
        // Romaji text needs no romaji over it.
        #expect(content.romajiWords.isEmpty)
    }

    @Test func inlineReadingsMove() {
        let content = RubyContent.content(for: Self.sentence).withInlineReadings(in: .hiragana)
        #expect(content.string == "今日（きょう）は東京（とうきょう）へ行（い）きたい。")
        #expect(words(of: content) == ["今日（きょう）", "は", "東京（とうきょう）", "へ", "行（い）き", "たい"])
    }

    @Test func rangesMapFromTheOriginal() {
        let original = RubyContent.content(for: Self.sentence)
        let content = original.transcribed(to: .romaji)
        // 東京 is offsets 3..<5 of the original.
        #expect(RubyReadingUnits.substring(of: content.string, utf16Range: content.range(fromOriginal: 3..<5)) == "tōkyō")
        // A phrase, 東京へ, takes in the space between its words.
        #expect(RubyReadingUnits.substring(of: content.string, utf16Range: content.range(fromOriginal: 3..<6)) == "tōkyō e")
        // Content that wasn't rewritten keeps its ranges.
        #expect(original.range(fromOriginal: 3..<5) == 3..<5)
        #expect(content.sourceString == Self.sentence)
    }

    @Test func wordBoundariesMapToTheEndOfTheWordBefore() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .romaji)
        // After 今日, before the space: kyō| wa.
        #expect(content.offset(fromOriginal: 2) == 3)
    }

    @Test func dictionaryWordsMove() {
        let content = RubyContent.content(for: "日本語を勉強した。").transcribed(to: .hiragana)
        let words = content.dictionaryWords.map { RubyReadingUnits.substring(of: content.string, utf16Range: $0) }
        #expect(words == ["にほんご", "を", "べんきょうした"])
    }

    @Test func rewritingIsCached() {
        let original = RubyContent.content(for: Self.sentence)
        #expect(original.transcribed(to: .hiragana) === original.transcribed(to: .hiragana))
        #expect(original.transcribed(to: .hiragana) !== original.transcribed(to: .katakana))
    }
}
