import CoreGraphics
import RubyCore
@testable import RubyUI
import Testing

@Suite struct RubyStyleTests {
    @Test func romajiAloneGoAbove() {
        #expect(RubyStyle.romaji.romajiAbove)
        #expect(!RubyStyle([.furigana, .romaji]).romajiAbove)
        #expect(!RubyStyle.furigana.romajiAbove)
        #expect(!RubyStyle().romajiAbove)
    }

    @Test func katakanaFurigana() {
        let measurements = RubyMeasurements(
            content: RubyContent.content(for: "東京で{本気|まじ}に{歩|ある}く"),
            furiganaScript: .katakana,
            baseWidth: { CGFloat($0.count) },
            annotationWidth: { CGFloat($0.count) / 2 }
        )
        #expect(measurements.furigana.map(\.text) == ["トウキョウ", "マジ", "アル"])
    }

    @Test func hiraganaFuriganaKeepMarkupSpelling() {
        let measurements = RubyMeasurements(
            content: RubyContent.content(for: "{本気|マジ}で東京"),
            baseWidth: { CGFloat($0.count) },
            annotationWidth: { CGFloat($0.count) / 2 }
        )
        #expect(measurements.furigana.map(\.text) == ["マジ", "とうきょう"])
    }
}
