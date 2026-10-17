import CoreGraphics
import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Romaji under each kana: where they go, which kana have them, and the
/// space they take, measured with every base character one unit wide and
/// every annotation character half a unit.
@Suite struct RubyKanaRomajiUITests {
    private static let romajiSpacing = 0.2

    /// わたしは学生です。, as an app gives it.
    private static let student = RubyContent.content(for: [
        RubySegment("わたし", wordID: "watashi"),
        RubySegment("は", word: .init(attachesToPrevious: true), wordID: "wa"),
        RubySegment("学生", reading: "がくせい", word: .init(attachesToPrevious: false), wordID: "gakusei"),
        RubySegment("です", word: .init(attachesToPrevious: true), wordID: "desu"),
        RubySegment("。", source: .dictionary),
    ])

    @Test func kanaRomajiGoBelowWithFuriganaAbove() {
        #expect(RubyPlacement(style: [.furigana, .kanaRomaji]) == RubyPlacement(furigana: true, romajiAbove: false, romajiBelow: false, kanaRomaji: true))
        #expect(RubyPlacement(style: .kanaRomaji) == RubyPlacement(furigana: false, romajiAbove: false, romajiBelow: false, kanaRomaji: true))
    }

    @Test func romajiForEveryWordLeaveNoneUnderKana() {
        #expect(RubyPlacement(style: [.furigana, .romaji, .kanaRomaji]) == RubyPlacement(furigana: true, romajiAbove: false, romajiBelow: true))
        #expect(RubyPlacement(style: [.romaji, .kanaRomaji]) == RubyPlacement(furigana: false, romajiAbove: true, romajiBelow: false))
    }

    @Test func rewrittenTextHasNoKanaRomaji() {
        #expect(!RubyPlacement(style: [.furigana, .kanaRomaji], transcription: .hiragana).kanaRomaji)
        #expect(!RubyPlacement(style: [.furigana, .kanaRomaji], furiganaPosition: .inline).kanaRomaji)
        // Inline furigana only rewrite the text when furigana show.
        #expect(RubyPlacement(style: .kanaRomaji, furiganaPosition: .inline).kanaRomaji)
    }

    @Test func knownKanaHaveNoRomaji() {
        let filter = RubyKanaRomajiFilter.except(["わ", "た"])
        #expect(!filter.showsRomaji(under: "わ"))
        #expect(filter.showsRomaji(under: "し"))
        #expect(RubyKanaRomajiFilter.all.showsRomaji(under: "わ"))
        // Kana are matched as written: か and カ are learned apart.
        #expect(RubyKanaRomajiFilter.except(["か"]).showsRomaji(under: "カ"))
    }

    @Test func aKanaWithASmallOneIsKnownWholeOrByItsKana() {
        #expect(!RubyKanaRomajiFilter.except(["きゃ"]).showsRomaji(under: "きゃ"))
        #expect(!RubyKanaRomajiFilter.except(["き", "ゃ"]).showsRomaji(under: "きゃ"))
        #expect(RubyKanaRomajiFilter.except(["き"]).showsRomaji(under: "きゃ"))
    }

    @Test func hiddenWordsHaveNoRomaji() {
        let filter = RubyKanaRomajiFilter.all.hiding(wordIDs: ["wa"])
        #expect(!filter.showsRomaji(under: "は", wordID: "wa"))
        #expect(filter.showsRomaji(under: "は", wordID: "watashi"))
        #expect(filter.showsRomaji(under: "は"))
    }

    // MARK: Measuring and spacing

    private func measurements(_ content: RubyContent, kanaRomaji: Bool = true) -> RubyMeasurements {
        RubyMeasurements(
            content: content,
            kanaRomaji: kanaRomaji,
            baseWidth: { text, _ in CGFloat(text.count) },
            annotationWidth: { text, _ in CGFloat(text.count) / 2 }
        )
    }

    private func tracking(_ content: RubyContent, strength: CGFloat = 1, visibility: [Double]? = nil) -> [CGFloat] {
        let measurements = measurements(content)
        return RubyLayout.spacing(
            measurements: measurements,
            furigana: 0,
            romaji: 0,
            readingVisibility: .zero,
            romajiVisibility: .zero,
            kanaRomaji: strength,
            kanaRomajiVisibility: RubyAnimatableVector(values: visibility ?? measurements.kanaRomaji.map { _ in 1 }),
            wordGaps: .zero,
            fontSize: 1,
            romajiSpacing: Self.romajiSpacing
        ).tracking
    }

    @Test func kanaRomajiAreMeasuredOnlyWhenShown() {
        #expect(measurements(Self.student).kanaRomaji.map(\.text) == ["wa", "ta", "shi", "wa", "de", "su"])
        #expect(measurements(Self.student, kanaRomaji: false).kanaRomaji.isEmpty)
    }

    @Test func beatsThatFitTakeNoSpace() {
        #expect(tracking(.content(for: [RubySegment("あいう")])).allSatisfy { $0 == 0 })
    }

    /// Two beats as wide as their kana touch, so they're moved apart by
    /// half the space between romaji words.
    @Test func beatsThatTouchMoveApart() {
        let content = RubyContent.content(for: [RubySegment("かな")])
        let spaced = tracking(content)
        #expect(abs(spaced[0] - Self.romajiSpacing / 2) < 1e-9)
        #expect(spaced[1] == 0)
        // Hidden beats and hidden kana romaji take no space.
        #expect(tracking(content, visibility: [0, 1]) == [0, 0])
        #expect(tracking(content, strength: 0) == [0, 0])
    }

    private func layout(_ content: RubyContent, strength: CGFloat, visibility: [Double]) -> RubyLayout {
        RubyLayout(
            measurements: measurements(content),
            furigana: 1,
            romaji: 0,
            readingVisibility: .zero,
            romajiVisibility: .zero,
            kanaRomaji: strength,
            kanaRomajiVisibility: RubyAnimatableVector(values: visibility),
            wordGaps: .zero,
            fontSize: 1,
            romajiSpacing: Self.romajiSpacing,
            lineBreaking: .phrases,
            insertedSpaceWidth: 0,
            textColors: [],
            backgrounds: []
        )
    }

    @Test func shownBeatsAreDrawnAsVisibleAsTheFilterSays() {
        let layout = layout(Self.student, strength: 1, visibility: [0, 0, 1, 0.5, 0, 0])
        let romaji = layout.paragraphs.flatMap(\.kanaRomaji)
        #expect(romaji.map(\.text) == ["shi", "wa"])
        #expect(romaji.map(\.opacity) == [1, 0.5])
        #expect(self.layout(Self.student, strength: 0, visibility: [1, 1, 1, 1, 1, 1]).paragraphs.allSatisfy { $0.kanaRomaji.isEmpty })
    }

    /// Romaji are drawn, not written into the text, so VoiceOver,
    /// selection and copy have the text as it's written.
    @Test func theTextStaysAsWritten() {
        let layout = layout(Self.student, strength: 1, visibility: [1, 1, 1, 1, 1, 1])
        #expect(String(layout.text.characters) == "わたしは学生です。")
    }
}
