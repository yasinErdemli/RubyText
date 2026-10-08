import CoreGraphics
import RubyCore
@testable import RubyUI
import Testing

/// Spacing for annotations, measured with every base character one unit
/// wide and every annotation character half a unit, so results don't
/// depend on fonts.
@Suite struct RubyLayoutTests {
    private static let romajiSpacing = 0.2

    private struct Spaced {
        let measurements: RubyMeasurements
        let tracking: [CGFloat]
        let shifts: [CGFloat]
    }

    private func spaced(_ markup: String, furigana: CGFloat = 1, romaji: CGFloat = 0) -> Spaced {
        let measurements = RubyMeasurements(
            content: RubyContent.content(for: markup),
            baseWidth: { CGFloat($0.count) },
            annotationWidth: { CGFloat($0.count) / 2 }
        )
        let spacing = RubyLayout.spacing(
            measurements: measurements,
            furigana: furigana,
            romaji: romaji,
            readingVisibility: .zero,
            romajiVisibility: .zero,
            wordGaps: .zero,
            fontSize: 1,
            romajiSpacing: Self.romajiSpacing
        )
        return Spaced(measurements: measurements, tracking: spacing.tracking, shifts: spacing.shifts)
    }

    @Test func readingsOverhangNeighboringKana() {
        // とうきょう is half a unit wider than 東京; は and の take it.
        let result = spaced("は{東京|とうきょう}の")
        #expect(result.tracking.allSatisfy { $0 == 0 })
        #expect(result.shifts.allSatisfy { $0 == 0 })
    }

    @Test func spaceGoesAroundTheWord() {
        // Two units wider than 東京, between kanji that take none of it.
        let result = spaced("{漢|かん}{東京|あいうえかきくけ}{字|じ}")
        #expect(result.tracking == [0, 0, 2, 0])
        #expect(result.shifts == [0, 1, 1, 0])
    }

    @Test func readingsOverhangLettersAndDigits() {
        // さんびゃくさんじゅうさん is 3 units wider than 333. It starts with
        // the paragraph, and m and half of で take 1.5 units of it.
        let result = spaced("{333|さんびゃくさんじゅうさん}mで")
        #expect(result.shifts[0] == 0)
        #expect(result.tracking[2] == 1.5)
    }

    @Test func readingsShareTheSpaceBetweenThem() {
        // The space between 東京 and 大阪 goes to both readings, not just one.
        let result = spaced("{東京|とうきょうとうきょう}・{大阪|おおさかおおさか}")
        let gap = result.tracking[1] + result.shifts[3]
        #expect(gap > 0)
    }

    @Test func readingsStartWithTheParagraph() {
        // さむらい starts with 侍 instead of indenting it.
        let result = spaced("{侍|さむらい}の")
        #expect(result.shifts[0] == 0)
        #expect(result.tracking[0] == 0.5)
    }

    @Test(arguments: [
        "侍の魂と志を胸に、暁の湖で雷を待つ。",
        "今日、政府は新しい経済政策を発表した。\n東京の駅前で記者会見が行われた。",
        "コーヒーを飲みながら日本語を勉強しています。",
    ])
    func spaceIsNeverAddedInsideWords(_ text: String) {
        let result = spaced(text, furigana: 1, romaji: 1)
        for word in result.measurements.romaji {
            for index in word.characters.dropLast() {
                #expect(result.tracking[index] == 0, "inside \(word.text)")
            }
        }
        for reading in result.measurements.furigana {
            for index in reading.characters.dropLast() {
                #expect(result.tracking[index] == 0, "inside \(reading.text)")
            }
        }
    }

    @Test(arguments: [
        "侍の魂と志を胸に、暁の湖で雷を待つ。",
        "今日は東京へ行きたい。コーヒーを飲みながら日本語を勉強しています。",
        "2026年3月3日に出発する。",
    ])
    func romajiDontCollide(_ text: String) {
        let result = spaced(text, furigana: 1, romaji: 1)
        let characters = result.measurements.characters
        let widths = result.measurements.widths
        var x = [CGFloat](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            x[index + 1] = x[index] + widths[index] + result.tracking[index]
        }

        var previousRight: CGFloat?
        for word in result.measurements.romaji {
            let first = word.characters.lowerBound
            let last = word.characters.upperBound - 1
            let center = (x[first] + result.shifts[first] + x[last] + result.shifts[last] + widths[last]) / 2
            // At the start of the text, romaji start with it.
            let left = previousRight == nil ? max(center - word.width / 2, 0) : center - word.width / 2
            if let previousRight {
                #expect(left >= previousRight + Self.romajiSpacing - 0.001, "\(word.text) collides")
            }
            previousRight = left + word.width
        }
        // Romaji past the end get room after the last character.
        #expect(previousRight ?? 0 <= x[characters.count] + 0.001)
    }
}
