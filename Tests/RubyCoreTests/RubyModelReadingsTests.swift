import Foundation
@testable import RubyCore
import Testing

/// Picks the choice whose meaning mentions `keyword`, standing in for the
/// model.
private struct KeywordChooser: RubyReadingChooser {
    let keyword: String

    func choose(_ question: RubyReadingQuestion) async throws -> Int? {
        question.choices.firstIndex { $0.meaning.contains(keyword) }
    }
}

/// Picks the first choice whose meaning mentions one of `keywords`.
private struct KeywordsChooser: RubyReadingChooser {
    let keywords: [String]

    func choose(_ question: RubyReadingQuestion) async throws -> Int? {
        question.choices.firstIndex { choice in keywords.contains { choice.meaning.contains($0) } }
    }
}

@Suite struct RubyModelReadingsTests {
    private func questions(_ text: String) -> [RubyReadingQuestion] {
        let segments = RubyContent.segments(in: text, analyzer: RubyMeCabAnalyzer.ipadic)
        return RubyModelReadings.questions(in: segments).map(\.question)
    }

    @Test func asksAboutWordsOnTheList() {
        let market = "三月一日、大家さんと人気のない早朝の魚市場へ行き、辛い生物を一日中食べたら寒気がした。"
        let asked = questions(market)
        #expect(asked.map(\.word) == ["大家", "人気", "辛い", "生物", "寒気"])
        #expect(asked.allSatisfy { $0.sentence == market })
        #expect(asked[1].context == "さんと人気のない")
        #expect(questions("日本語を勉強している。").isEmpty)
    }

    @Test(arguments: [
        ("車を止めた。", "止め", ["とめ", "やめ"]),
        ("タバコを止めることにした。", "止める", ["とめる", "やめる"]),
        ("このカレーは辛すぎる。", "辛", ["から", "つら"]),
        ("お腹が空いた。", "空い", ["あい", "すい"]),
    ])
    func choicesFollowTheInflection(_ text: String, _ word: String, _ readings: [String]) {
        let question = questions(text).first
        #expect(question?.word == word)
        #expect(question?.choices.map(\.reading) == readings)
    }

    @Test func sentencesAreAskedAboutSeparately() {
        let asked = questions("別れは辛い。\nこのカレーは辛い！")
        #expect(asked.map(\.sentence) == ["別れは辛い。", "このカレーは辛い！"])
    }

    @Test func choicesReplaceOnlyTheReading() async {
        let text = "夜の公園は人気がない。"
        let dictionary = RubyContent.content(for: text)
        let content = await RubyContent.content(for: text, chooser: KeywordChooser(keyword: "deserted"))
        #expect(content.words.map(\.range) == dictionary.words.map(\.range))
        let word = content.words.first { $0.furigana.first?.text == "ひとけ" }
        #expect(word?.source == .model)
        #expect(word?.romaji == "hitoke")
    }

    @Test func readingsComeAsAnswered() async {
        var updates: [[String]] = []
        let content = await RubyContent.content(
            for: "夜の公園は人気がない。このカレーは辛い！",
            analyzer: RubyMeCabAnalyzer.ipadic,
            chooser: KeywordsChooser(keywords: ["deserted", "spicy"])
        ) { content in
            updates.append(content.words.filter { $0.source == .model }.flatMap(\.furigana).map(\.text))
        }
        // One update for each reading changed, each with the ones before.
        #expect(updates == [["ひとけ"], ["ひとけ", "から"]])
        #expect(content.words.filter { $0.source == .model }.flatMap(\.furigana).map(\.text) == ["ひとけ", "から"])
    }

    @Test func forgottenReadingsAreChosenAgain() async {
        func updates() async -> Int {
            var count = 0
            _ = await RubyContent.content(
                for: "受付の方に聞いてください。",
                analyzer: RubyMeCabAnalyzer.ipadic,
                chooser: KeywordsChooser(keywords: ["polite"])
            ) { _ in count += 1 }
            return count
        }
        #expect(await updates() == 1)
        // Kept, so nothing changes as it's shown again.
        #expect(await updates() == 0)
        RubyModelReadings.forgetAnswers()
        #expect(await updates() == 1)
    }

    @Test func agreeingWithTheDictionaryChangesNothing() async {
        let text = "人気のある店に行った。"
        let content = await RubyContent.content(for: text, chooser: KeywordChooser(keyword: "popularity"))
        #expect(content === RubyContent.content(for: text))
    }

    @Test func manualReadingsAreNeverAsked() {
        #expect(questions("夜の公園は人気がない。").count == 1)
        let segments = RubyContent.segments(in: "夜の公園は人気がない。", analyzer: RubyMeCabAnalyzer.ipadic)
        #expect(RubyModelReadings.questions(in: segments, excluding: [5..<7]).isEmpty)
    }
}
