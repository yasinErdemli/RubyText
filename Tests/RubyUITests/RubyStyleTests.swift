import CoreGraphics
import RubyCore
@testable import RubyUI
import Testing

@Suite struct RubyStyleTests {
    @Test func romajiGoBelowFuriganaOnly() {
        #expect(RubyPlacement(style: .romaji) == placement(romajiAbove: true))
        #expect(RubyPlacement(style: [.furigana, .romaji]) == placement(furigana: true, romajiBelow: true))
        #expect(RubyPlacement(style: .furigana) == placement(furigana: true))
        #expect(RubyPlacement(style: []) == placement())
    }

    @Test func inlineFuriganaLeaveTheSpaceAboveToRomaji() {
        #expect(RubyPlacement(style: [.furigana, .romaji], furiganaPosition: .inline) == placement(romajiAbove: true))
    }

    @Test func transcribedTextHasNoFurigana() {
        #expect(RubyPlacement(style: [.furigana, .romaji], transcription: .hiragana) == placement(romajiAbove: true))
        // Nor romaji over romaji.
        #expect(RubyPlacement(style: [.furigana, .romaji], transcription: .romaji) == placement())
    }

    private func placement(furigana: Bool = false, romajiAbove: Bool = false, romajiBelow: Bool = false) -> RubyPlacement {
        RubyPlacement(furigana: furigana, romajiAbove: romajiAbove, romajiBelow: romajiBelow)
    }

    @Test func furiganaScripts() {
        func furigana(_ markup: String, in script: RubyScript = .hiragana) -> [String] {
            RubyMeasurements(
                content: RubyContent.content(for: markup),
                furiganaScript: script,
                baseWidth: { CGFloat($0.count) },
                annotationWidth: { CGFloat($0.count) / 2 }
            ).furigana.map(\.text)
        }
        #expect(furigana("東京で{本気|まじ}に{歩|ある}く", in: .katakana) == ["トウキョウ", "マジ", "アル"])
        #expect(furigana("東京で{本気|まじ}に{歩|ある}く", in: .romaji) == ["tōkyō", "maji", "aru"])
        // In hiragana, markup readings keep their kana.
        #expect(furigana("{本気|マジ}で東京") == ["マジ", "とうきょう"])
    }
}
