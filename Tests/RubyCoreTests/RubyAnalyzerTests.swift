// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import Foundation
import Synchronization
@_spi(Experiments) import RubyCore
import RubyMeCab
import Testing

/// Reads all of its text as one noun with a fixed reading.
private struct FixedAnalyzer: RubyAnalyzer {
    let reading: String

    func segments(in text: String) -> [RubySegment] {
        [RubySegment(text, reading: reading, word: .init(partOfSpeech: .noun), source: .dictionary)]
    }
}

@Suite struct RubyAnalyzerTests {
    @Test func ipadicFindsReadings() {
        let content = RubyContent.content(for: "猫", analyzer: RubyMeCabAnalyzer.ipadic)
        #expect(content.words.map(\.romaji) == ["neko"])
    }

    @Test func withoutAnAnalyzerOnlyMarkupIsRead() {
        let content = RubyContent.content(for: "{猫|ねこ}と犬", analyzer: nil)
        #expect(content.string == "猫と犬")
        #expect(content.words.flatMap(\.furigana).map(\.text) == ["ねこ"])
    }

    @Test func aMissingDictionaryReadsNothing() {
        let analyzer = RubyMeCabAnalyzer(dictionary: URL(filePath: "/nonexistent"))
        #expect(analyzer.segments(in: "猫").compactMap(\.reading).isEmpty)
    }

    /// IPAdic reads words it doesn't know as written, without a
    /// pronunciation, and guesses they're names: the long vowel comes from
    /// spelling, and the word isn't capitalized.
    @Test func unknownWordsAreReadAsWritten() {
        let converter = RubyConverter(analyzer: RubyMeCabAnalyzer.ipadic)
        #expect(converter.convert("ｶﾞｯｺｳ", to: .romaji) == "gakkō")
        #expect(converter.convert("ガッコウ", to: .romaji) == "gakkō")
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

    @Test func shortTextIsAnalyzedAtOnce() {
        let analyzer = FixedAnalyzer(reading: "みじかい")
        let short = RubyString(markup: "短い文")
        let content = RubyContent.immediateContent(for: short, analyzer: analyzer)
        #expect(content?.words.flatMap(\.furigana).map(\.text) == ["みじかい"])
        #expect(RubyContent.cachedContent(for: short, analyzer: analyzer) === content)
    }

    @Test func longTextIsAnalyzedLater() async {
        let analyzer = FixedAnalyzer(reading: "ながい")
        let long = RubyString(markup: String(repeating: "長", count: RubyContent.immediateLength + 1))
        #expect(RubyContent.immediateContent(for: long, analyzer: analyzer) == nil)
        // Without an analyzer, there's nothing to wait for.
        #expect(RubyContent.immediateContent(for: long, analyzer: nil) != nil)

        let content = await RubyContent.analyzing(long, analyzer: analyzer)
        #expect(content.words.flatMap(\.furigana).map(\.text) == ["ながい"])
        #expect(RubyContent.immediateContent(for: long, analyzer: analyzer) === content)
    }

    @MainActor
    @Test func analysisLeavesTheMainActor() async {
        let analyzer = ThreadRecordingAnalyzer()
        _ = await RubyContent.analyzing(RubyString(markup: "本を読む"), analyzer: analyzer)
        #expect(analyzer.ranOnMainThread == [false])

        let chosen = ThreadRecordingAnalyzer()
        _ = await RubyContent.content(for: "辛い", analyzer: chosen, chooser: FirstChooser())
        #expect(chosen.ranOnMainThread == [false])
    }
}

/// Reads each text as one noun, and records whether it did so on the main
/// thread.
private final class ThreadRecordingAnalyzer: RubyAnalyzer {
    private let calls = Mutex<[Bool]>([])
    var ranOnMainThread: [Bool] { calls.withLock { $0 } }

    func segments(in text: String) -> [RubySegment] {
        calls.withLock { $0.append(Thread.isMainThread) }
        return [RubySegment(text, reading: "よむ", word: .init(partOfSpeech: .noun), source: .dictionary)]
    }

    static func == (lhs: ThreadRecordingAnalyzer, rhs: ThreadRecordingAnalyzer) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Always picks the first reading.
private struct FirstChooser: RubyReadingChooser {
    func choose(_ question: RubyReadingQuestion) async throws -> Int? { 0 }
}
#endif
