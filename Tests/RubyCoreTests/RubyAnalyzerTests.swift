import RubyCore
import Testing

/// Reads all of its text as one noun with a fixed reading.
private struct FixedAnalyzer: RubyAnalyzer {
    let reading: String

    func segments(in text: String) -> [RubySegment] {
        [RubySegment(text, reading: reading, word: .init(partOfSpeech: .noun), source: .dictionary)]
    }
}

@Suite struct RubyAnalyzerTests {
    @Test func mecabIsTheDefault() {
        let content = RubyContent.content(for: "猫")
        #expect(content.words.map(\.romaji) == ["neko"])
    }

    @Test func contentUsesTheGivenAnalyzer() {
        let content = RubyContent.content(for: "生物", analyzer: FixedAnalyzer(reading: "なまもの"))
        #expect(content.words.flatMap(\.furigana).map(\.text) == ["なまもの"])
        #expect(content.words.first?.source == .dictionary)
    }

    @Test func contentIsCachedPerAnalyzer() {
        let raw = FixedAnalyzer(reading: "なまもの")
        let first = RubyContent.content(for: "生物", analyzer: raw)
        #expect(RubyContent.content(for: "生物", analyzer: FixedAnalyzer(reading: "なまもの")) === first)

        let other = RubyContent.content(for: "生物", analyzer: FixedAnalyzer(reading: "せいぶつ"))
        #expect(other !== first)
        #expect(other.words.flatMap(\.furigana).map(\.text) == ["せいぶつ"])
    }

    @Test func manualReadingsOverrideTheAnalyzer() {
        let content = RubyContent.content(for: "{生物|いきもの}", analyzer: FixedAnalyzer(reading: "せいぶつ"))
        #expect(content.words.flatMap(\.furigana).map(\.text) == ["いきもの"])
        #expect(content.words.first?.source == .manual)
    }
}
