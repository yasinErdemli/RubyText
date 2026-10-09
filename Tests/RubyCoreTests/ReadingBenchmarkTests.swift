import Foundation
import RubyCore
import RubyTransliteration
import Testing

/// The reading the default analyzer gives `word` in `sentence`: kana as
/// written, with each kanji run replaced by its furigana. `nil` if `word`
/// isn't in the sentence or a reading straddles its edges.
func reading(of word: String, in sentence: String) -> String? {
    reading(of: word, in: RubyContent.content(for: sentence))
}

/// The reading of `word`'s first occurrence in `content`.
func reading(of word: String, in content: RubyContent) -> String? {
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
    return RubyKana.hiragana(result)
}

extension BenchmarkCase {
    var actual: String? { reading(of: word, in: sentence) }
    var isCorrect: Bool { actual.map(readings.contains) ?? false }
}

@Suite struct ReadingBenchmarkTests {
    @Test(arguments: readingBenchmark)
    func reads(_ benchmark: BenchmarkCase) {
        let actual = benchmark.actual ?? "(not found)"
        let expected = benchmark.readings.joined(separator: " or ")
        if benchmark.isCorrect {
            if let mecab = benchmark.mecab {
                Issue.record("Now reads \(actual), no longer \(mecab): remove `mecab:`")
            }
        } else if actual == benchmark.mecab {
            withKnownIssue("\(benchmark.kind.rawValue) error, not fixed yet") {
                Issue.record("Reads \(actual), should be \(expected), in \(benchmark.sentence)")
            }
        } else {
            let was = benchmark.mecab.map { " (recorded as \($0))" } ?? ""
            Issue.record("Reads \(actual)\(was), should be \(expected), in \(benchmark.sentence)")
        }
    }

    @Test func casesAreUnique() {
        let keys = readingBenchmark.map { "\($0.word)\t\($0.sentence)" }
        #expect(Set(keys).count == keys.count)
    }

    /// Prints the score by kind as a Markdown table for the README, then
    /// each wrong reading.
    @Test func score() {
        func row(_ name: String, _ cases: [BenchmarkCase]) -> String {
            let correct = cases.filter(\.isCorrect).count
            let percent = cases.isEmpty ? 0 : Int((Double(correct) / Double(cases.count) * 100).rounded())
            return "| \(name) | \(correct) of \(cases.count) | \(percent)% |"
        }
        var lines = ["| Kind | Correct | |", "| --- | --- | --- |"]
        for kind in BenchmarkCase.Kind.allCases {
            lines.append(row(kind.rawValue, readingBenchmark.filter { $0.kind == kind }))
        }
        lines.append(row("**All**", readingBenchmark))
        lines.append("")
        for kind in BenchmarkCase.Kind.allCases {
            for wrong in readingBenchmark where wrong.kind == kind && !wrong.isCorrect {
                lines.append("- \(kind.rawValue): \(wrong.word) → \(wrong.actual ?? "(not found)"), should be \(wrong.readings[0])")
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
