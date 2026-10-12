import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Furigana, colors and spacing for segments an app gives, with IDs on
/// their words.
@Suite struct RubyWordIDTests {
    /// 食べ物を食べた, with 食 known but 食べ物 still being learned.
    private static let content = RubyContent.content(for: [
        RubySegment("食", reading: "た", wordID: "food"),
        RubySegment("べ", wordID: "food"),
        RubySegment("物", reading: "もの", wordID: "food"),
        RubySegment("を", word: .init(attachesToPrevious: true), wordID: "o"),
        RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "eat"),
        RubySegment("べた", wordID: "eat"),
    ])

    /// Whether each reading in `content` shows with `filter`, as `RubyText`
    /// asks.
    private func shown(_ filter: RubyFuriganaFilter) -> [Bool] {
        Self.content.words.flatMap { word in
            word.furigana.map { reading in
                filter.showsReading(
                    over: RubyReadingUnits.substring(of: Self.content.string, utf16Range: reading.range),
                    wordID: word.wordID
                )
            }
        }
    }

    /// A word shown by ID shows all its readings; the same kanji elsewhere
    /// keep to the filter.
    @Test func shownWordsShowEveryReading() {
        #expect(shown(.except(["食"])) == [false, true, false])
        #expect(shown(.except(["食"]).showing(wordIDs: ["food"])) == [true, true, false])
        #expect(shown(.except(["食", "物"]).showing(wordIDs: ["eat"])) == [false, false, true])
        #expect(shown(.all.showing(wordIDs: ["food"])) == [true, true, true])
    }

    @Test func showingIsPartOfTheFilter() {
        #expect(RubyFuriganaFilter.except(["食"]).showing(wordIDs: ["food"]) != .except(["食"]))
        #expect(RubyFuriganaFilter.except(["食"]).showing(wordIDs: ["food"]).showing(wordIDs: ["eat"])
            == .except(["食"]).showing(wordIDs: ["food", "eat"]))
    }

    /// Only the words with the IDs are colored, not others written the
    /// same.
    @Test func wordIDsColorTheirWords() {
        let words = Self.content.words
        #expect(RubyWordColors.wordIDs(["food"], color: .red).colors(for: words, in: Self.content.string) == [.red, nil, nil])
        #expect(RubyWordColors.wordIDs(["eat": .blue]).colors(for: words, in: Self.content.string) == [nil, nil, .blue])

        let cats = RubyContent.content(for: [
            RubySegment("猫", reading: "ねこ", wordID: "cat 1"),
            RubySegment("と", wordID: "to"),
            RubySegment("猫", reading: "ねこ", wordID: "cat 2"),
        ])
        #expect(RubyWordColors.wordIDs(["cat 2"], color: .red).colors(for: cats.words, in: cats.string) == [nil, nil, .red])
        #expect(RubyWordColors.words(["猫"], color: .red).colors(for: cats.words, in: cats.string) == [.red, nil, .red])
    }

    /// Only the words with the IDs get a weight, bold unless another is
    /// given.
    @Test func wordIDsWeighTheirWords() {
        let words = Self.content.words
        #expect(RubyWordWeights.wordIDs(["food"]).weights(for: words, in: Self.content.string) == [.bold, nil, nil])
        #expect(RubyWordWeights.wordIDs(["eat": .heavy]).weights(for: words, in: Self.content.string) == [nil, nil, .heavy])
        #expect(RubyWordWeights.words(["食べ物"], weight: .semibold).weights(for: words, in: Self.content.string) == [.semibold, nil, nil])
    }

    /// Phrases are spaced where the app starts them: 今日 何を.
    @Test func phrasesAreSpacedWhereGiven() {
        let content = RubyContent.content(for: [
            RubySegment("今日", reading: "きょう", word: .init(attachesToPrevious: false)),
            RubySegment("何", reading: "なに", word: .init(attachesToPrevious: false)),
            RubySegment("を", word: .init(attachesToPrevious: true)),
        ])
        #expect(RubySpacing.phrases.boundaries(in: content) == [2])
        // And pieces of a word aren't spaced apart.
        #expect(RubySpacing.phrases.boundaries(in: Self.content) == [4])
    }
}
