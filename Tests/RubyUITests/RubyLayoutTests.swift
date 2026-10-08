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
        #expect(result.tracking == [1, 0, 1, 0])
        #expect(result.shifts == [0, 0, 0, 0])
    }

    @Test func readingsFlowOverCharactersWithoutReadings() {
        // The reading is 3 units wider than 東. It starts with the
        // paragraph, and flows over m and で, which take 2 units of it.
        let result = spaced("{東|あいうえおかきく}mで")
        #expect(result.shifts[0] == 0)
        #expect(result.tracking[0] == 1)
    }

    @Test func readingsOverDigitsAreNarrowed() {
        // さんびゃくさんじゅうさん (6 units) narrows to the 5 units of 333,
        // m, and で, so nothing moves.
        let fitting = spaced("{333|さんびゃくさんじゅうさん}mで")
        #expect(abs((fitting.measurements.furigana.first?.scale ?? 0) - 5.0 / 6.0) < 0.0001)
        #expect(fitting.tracking.allSatisfy { $0 == 0 })

        // Narrowed no further than three quarters: 5 units become 3.75.
        let long = spaced("{3|あいうえおかきくけこ}")
        #expect(long.measurements.furigana.first?.scale == RubyMeasurements.minimumScale)
        #expect(long.tracking[0] == 2.75)

        // Readings over kanji keep their width.
        #expect(spaced("{東|あいうえおかきく}mで").measurements.furigana.first?.scale == 1)
    }

    @Test func readingsShareTheSpaceBetweenThem() {
        // Both readings flow over ・ without meeting.
        let result = spaced("{東京|あいうえかきくけ}・{大阪|さしすせたちつて}")
        let widths = result.measurements.widths
        var x: [CGFloat] = [0]
        for index in widths.indices { x.append(x[index] + widths[index] + result.tracking[index]) }
        // The first reading starts with the paragraph; the second is
        // centered over 大阪. Each is 4 units wide.
        let firstEnd: CGFloat = 4
        let secondCenter = x[3] + result.shifts[3] + 1
        #expect(secondCenter - 2 - firstEnd >= 0.125 - 0.001)
        #expect(result.tracking[1] < 2, "・ took part of the space")
    }

    @Test func readingsStartWithTheParagraph() {
        // The reading starts with 侍 instead of indenting it, flows over
        // の, and needs 2 more units after it.
        let result = spaced("{侍|さむらいさむらい}の")
        #expect(result.shifts[0] == 0)
        #expect(result.tracking[0] == 2)
    }

    @Test func readingsEndWithTheParagraph() {
        // The reading ends with 侍, flows over の, and takes the rest of its
        // space before の: space after the last character doesn't count.
        let result = spaced("の{侍|さむらいさむらい}")
        #expect(result.tracking == [2, 0])
        #expect(result.shifts == [0, 0])
    }

    @Test(arguments: [
        "侍の魂と志を胸に、暁の湖で雷を待つ。",
        "帝の詔を謹んで承る。",
        "鶯が曙の頂で囀り、鷲が鬣を弄ぶ。",
        "夥しい鎧と兜が掌の上で恭しく並ぶ。",
        "今日、政府は新しい経済政策を発表した。\n東京の駅前で記者会見が行われた。",
        "コーヒーを飲みながら日本語を勉強しています。",
    ])
    func spaceIsNeverAddedInsideWords(_ text: String) {
        let result = spaced(text, furigana: 1, romaji: 1)
        // The visible space between a glyph and the next: the space added
        // after it, less how much further right the next one is shifted.
        func gap(after index: Int) -> CGFloat {
            result.tracking[index] + result.shifts[index + 1] - result.shifts[index]
        }
        for word in result.measurements.romaji {
            for index in word.characters.dropLast() {
                #expect(abs(gap(after: index)) < 0.0001, "inside \(word.text)")
            }
        }
        for reading in result.measurements.furigana {
            for index in reading.characters.dropLast() {
                #expect(abs(gap(after: index)) < 0.0001, "inside \(reading.text)")
            }
        }
    }

    @Test(arguments: [
        "侍の魂と志を胸に、暁の湖で雷を待つ。",
        "帝の詔を謹んで承る。",
        "鶯が曙の頂で囀り、鷲が鬣を弄ぶ。",
        "夥しい鎧と兜が掌の上で恭しく並ぶ。",
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
            var center = (x[first] + result.shifts[first] + x[last] + result.shifts[last] + widths[last]) / 2
            // Romaji start and end within the text.
            center = max(min(center, x[characters.count] - word.width / 2), word.width / 2)
            let left = center - word.width / 2
            if let previousRight {
                #expect(left >= previousRight + Self.romajiSpacing - 0.001, "\(word.text) collides")
            }
            previousRight = left + word.width
        }
        // No romaji runs past the end, where space doesn't widen the text.
        #expect(previousRight ?? 0 <= x[characters.count] + 0.001)
    }
}
