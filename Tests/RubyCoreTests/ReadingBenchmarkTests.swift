import Foundation
import RubyCore
import Testing

/// A word whose reading is easy to get wrong, in a sentence that decides it.
struct BenchmarkCase: Sendable, CustomTestStringConvertible {
    enum Kind: String, Sendable {
        /// Dates and numbers, which need their own rules.
        case number
        /// Fixed phrases a dictionary can list.
        case phrase
        /// Words whose reading depends on their meaning in context.
        case meaning
        /// Words the analyzer already reads correctly, kept as a guard.
        case control
    }

    let sentence: String
    let word: String
    /// The correct reading of `word`, in hiragana.
    let reading: String
    let kind: Kind
    /// Whether the default analyzer reads `word` correctly today. Cases
    /// that fail are known issues: the test passes until one starts
    /// working, then fails so the case can be marked fixed.
    let passes: Bool

    var testDescription: String { "\(word) → \(reading)" }
}

/// The accuracy benchmark from the roadmap: four test sentences, with
/// further cases worth tracking.
let readingBenchmark: [BenchmarkCase] = {
    let date = "2025年3月16日"
    let stress = "侍の魂と志を胸に、暁の湖で雷を待つ。"
    let market = "三月一日、大家さんと人気のない早朝の魚市場へ行き、辛い生物を一日中食べたら寒気がした。"
    let shop = "あの方は一枚上手で、気に入った店でも今日は止めておくと言った。"
    return [
        BenchmarkCase(sentence: date, word: date, reading: "にせんにじゅうごねんさんがつじゅうろくにち", kind: .number, passes: false),

        // The layout stress test: MeCab reads every word correctly.
        BenchmarkCase(sentence: stress, word: "侍", reading: "さむらい", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "魂", reading: "たましい", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "志", reading: "こころざし", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "胸", reading: "むね", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "暁", reading: "あかつき", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "湖", reading: "みずうみ", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "雷", reading: "かみなり", kind: .control, passes: true),
        BenchmarkCase(sentence: stress, word: "待つ", reading: "まつ", kind: .control, passes: true),

        // The twelve traps.
        BenchmarkCase(sentence: market, word: "三月一日", reading: "さんがつついたち", kind: .number, passes: false),
        BenchmarkCase(sentence: market, word: "大家さん", reading: "おおやさん", kind: .phrase, passes: true),
        BenchmarkCase(sentence: market, word: "人気", reading: "ひとけ", kind: .meaning, passes: false),
        BenchmarkCase(sentence: market, word: "魚市場", reading: "うおいちば", kind: .phrase, passes: true),
        BenchmarkCase(sentence: market, word: "辛い", reading: "からい", kind: .meaning, passes: false),
        BenchmarkCase(sentence: market, word: "生物", reading: "なまもの", kind: .meaning, passes: false),
        BenchmarkCase(sentence: market, word: "一日中", reading: "いちにちじゅう", kind: .phrase, passes: false),
        BenchmarkCase(sentence: market, word: "寒気", reading: "さむけ", kind: .phrase, passes: true),
        BenchmarkCase(sentence: shop, word: "あの方", reading: "あのかた", kind: .meaning, passes: false),
        BenchmarkCase(sentence: shop, word: "一枚上手", reading: "いちまいうわて", kind: .phrase, passes: false),
        BenchmarkCase(sentence: shop, word: "気に入った", reading: "きにいった", kind: .phrase, passes: true),
        BenchmarkCase(sentence: shop, word: "止めておく", reading: "やめておく", kind: .meaning, passes: false),

        // More cases worth tracking.
        BenchmarkCase(sentence: "人気のある店に行った。", word: "人気", reading: "にんき", kind: .meaning, passes: true),
        BenchmarkCase(sentence: "昨日は十分休んだ。", word: "十分", reading: "じゅうぶん", kind: .meaning, passes: true),
        BenchmarkCase(sentence: "十分後に出発します。", word: "十分後", reading: "じっぷんご", kind: .number, passes: false),
        BenchmarkCase(sentence: "株式市場が急落した。", word: "株式市場", reading: "かぶしきしじょう", kind: .phrase, passes: true),
        BenchmarkCase(sentence: "会議を行った。", word: "行った", reading: "おこなった", kind: .meaning, passes: true),
        BenchmarkCase(sentence: "大人になったら分かる。", word: "大人", reading: "おとな", kind: .control, passes: true),
    ]
}()

/// The reading the default analyzer gives `word` in `sentence`: kana as
/// written, with each kanji run replaced by its furigana. `nil` if `word`
/// isn't in the sentence or a reading straddles its edges.
func reading(of word: String, in sentence: String) -> String? {
    let content = RubyContent.content(for: sentence)
    guard let found = content.string.range(of: word) else { return nil }
    let utf16 = content.string.utf16
    let lower = utf16.distance(from: utf16.startIndex, to: found.lowerBound)
    let span = lower..<(lower + word.utf16.count)

    let furigana = content.words.flatMap(\.furigana).filter { $0.range.overlaps(span) }
    guard furigana.allSatisfy({ span.contains($0.range.lowerBound) && $0.range.upperBound <= span.upperBound }) else {
        return nil
    }
    var result = ""
    var position = span.lowerBound
    for reading in furigana.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        result += RubyReadingUnits.substring(of: content.string, utf16Range: position..<reading.range.lowerBound)
        result += reading.text
        position = reading.range.upperBound
    }
    result += RubyReadingUnits.substring(of: content.string, utf16Range: position..<span.upperBound)
    return RubyReadings.hiragana(result)
}

@Suite struct ReadingBenchmarkTests {
    @Test(arguments: readingBenchmark)
    func reads(_ benchmark: BenchmarkCase) {
        let actual = reading(of: benchmark.word, in: benchmark.sentence)
        if benchmark.passes {
            #expect(actual == benchmark.reading, "in \(benchmark.sentence)")
        } else {
            withKnownIssue("\(benchmark.kind.rawValue) error, not fixed yet") {
                #expect(actual == benchmark.reading, "in \(benchmark.sentence)")
            }
        }
    }

    /// Prints the score to publish in the README, by kind of error.
    @Test func score() {
        let results = readingBenchmark.map { ($0, reading(of: $0.word, in: $0.sentence) == $0.reading) }
        let correct = results.filter(\.1).count
        var lines = ["Reading accuracy: \(correct) of \(results.count)"]
        for kind in [BenchmarkCase.Kind.number, .phrase, .meaning, .control] {
            let ofKind = results.filter { $0.0.kind == kind }
            lines.append("  \(kind.rawValue): \(ofKind.filter(\.1).count) of \(ofKind.count)")
        }
        print(lines.joined(separator: "\n"))
        #expect(correct == readingBenchmark.filter(\.passes).count, "Update `passes` to match the results")
    }
}
