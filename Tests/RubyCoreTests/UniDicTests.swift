import Foundation
import RubyCore
import RubyMeCab
import Testing

/// MeCab with UniDic, at the path in the `RUBYTEXT_UNIDIC` environment
/// variable, since UniDic is too large to keep with the tests:
///
///     RUBYTEXT_UNIDIC=/path/to/unidic/dicdir swift test --filter UniDic
let unidic: RubyMeCabAnalyzer? = ProcessInfo.processInfo.environment["RUBYTEXT_UNIDIC"].map {
    RubyMeCabAnalyzer(dictionary: URL(filePath: $0))
}

@Suite(.enabled(if: unidic != nil, "Set RUBYTEXT_UNIDIC to a UniDic folder"))
struct UniDicTests {
    private let analyzer = unidic!

    @Test func readsUniDic() {
        #expect(analyzer.format == .unidic)
        let converter = RubyConverter(analyzer: analyzer)
        #expect(converter.annotate("東京へ行きたい。", with: .hiragana) == "東京（とうきょう）へ行（い）きたい。")
        #expect(converter.convert("今日はコーヒーを飲んだ。", to: .romaji) == "kyō wa kōhī o nonda.")
        #expect(converter.convert("東京へ行こう。", to: .romaji) == "Tōkyō e ikō.")
    }

    @Test func grammar() throws {
        let segments = analyzer.segments(in: "田中さんは家にいる。本を読んでいる。")
        func word(_ base: String, after index: Int = 0) throws -> RubySegment.Word {
            try #require(segments[index...].first { $0.base == base }?.word)
        }
        #expect(try word("田中").isProperNoun)
        #expect(try word("田中").partOfSpeech == .noun)
        #expect(try word("さん").attachesToPrevious == true)
        #expect(try word("は").partOfSpeech == .particle)
        #expect(try word("読ん").dictionaryForm == "読む")
        // いる after に stands alone; after て or で it attaches.
        let first = try #require(segments.firstIndex { $0.base == "いる" })
        #expect(segments[first].word?.attachesToPrevious == false)
        #expect(try word("いる", after: first + 1).attachesToPrevious == true)
    }

    @Test func rulesApply() {
        let converter = RubyConverter(analyzer: analyzer)
        #expect(converter.annotate("3日に6本買った。", with: .hiragana) == "3日（みっか）に6本（ろっぽん）買（か）った。")
    }

    @Test func benchmark() {
        let wrong = readingBenchmark.filter { benchmark in
            let content = RubyContent.content(for: benchmark.sentence, analyzer: analyzer)
            return !(reading(of: benchmark.word, in: content).map(benchmark.readings.contains) ?? false)
        }
        print("UniDic benchmark: \(readingBenchmark.count - wrong.count) of \(readingBenchmark.count)")
        for benchmark in wrong {
            let content = RubyContent.content(for: benchmark.sentence, analyzer: analyzer)
            print("- \(benchmark.kind.rawValue): \(benchmark.word) → \(reading(of: benchmark.word, in: content) ?? "(not found)"), should be \(benchmark.readings[0])")
        }
    }
}
