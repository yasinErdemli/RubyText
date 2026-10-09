import RubyCore
import RubyTransliteration
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
        #expect(content.romajiWords.map(\.text) == ["kyō", "wa", "Tōkyō", "e", "ikitai"])
    }

    @Test func katakana() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .katakana)
        #expect(content.string == "キョウハトウキョウヘイキタイ。")
        #expect(words(of: content).first == "キョウ")
    }

    @Test func romajiWordsMove() {
        let content = RubyContent.content(for: Self.sentence).transcribed(to: .romaji)
        #expect(content.string == "kyō wa Tōkyō e ikitai.")
        // 行き and たい share the romaji word ikitai, divided between them.
        #expect(words(of: content) == ["kyō", "wa", "Tōkyō", "e", "iki", "tai"])
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
        #expect(RubyReadingUnits.substring(of: content.string, utf16Range: content.range(fromOriginal: 3..<5)) == "Tōkyō")
        // A phrase, 東京へ, takes in the space between its words.
        #expect(RubyReadingUnits.substring(of: content.string, utf16Range: content.range(fromOriginal: 3..<6)) == "Tōkyō e")
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

    @Test func loanwordsStayInKatakana() {
        let original = RubyContent.content(for: "コーヒーを飲んだ。")
        #expect(original.transcribed(to: .hiragana).string == "コーヒーをのんだ。")
        #expect(original.transcribed(to: .hiragana(loanwords: .hiragana)).string == "こーひーをのんだ。")
    }

    @Test func kanaSpacedBetweenPhrases() {
        let original = RubyContent.content(for: Self.sentence)
        // After 今日は (offset 3) and 東京へ (offset 6).
        let content = original.transcribed(to: .hiragana, spacedAt: [3, 6])
        #expect(content.string == "きょうは\u{3000}とうきょうへ\u{3000}いきたい。")
        #expect(content.spaces == [4, 11])
        // Words don't take in the spaces around them.
        #expect(words(of: content) == ["きょう", "は", "とうきょう", "へ", "いき", "たい"])
        // Romaji are spaced as words regardless.
        #expect(original.transcribed(to: .romaji, spacedAt: [3, 6]).spaces.isEmpty)
    }

    @Test func romajiWordsInEachSystem() {
        let content = RubyContent.content(for: "新聞を読もう。")
        #expect(content.romajiWords(in: .hepburn).map(\.text) == ["shinbun", "o", "yomō"])
        #expect(content.romajiWords(in: .nippon).map(\.text) == ["sinbun", "wo", "yomô"])
        #expect(content.romajiWords(in: .passport).map(\.text) == ["shimbun", "o", "yomo"])
        // Hiragana text keeps romaji in every system over its words.
        let hiragana = content.transcribed(to: .hiragana)
        #expect(hiragana.romajiWords(in: .nippon).map(\.text) == ["sinbun", "wo", "yomô"])
    }

    @Test func rewritingIsCached() {
        let original = RubyContent.content(for: Self.sentence)
        #expect(original.transcribed(to: .hiragana) === original.transcribed(to: .hiragana))
        #expect(original.transcribed(to: .hiragana) !== original.transcribed(to: .katakana))
    }
}
