// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import CoreGraphics
import RubyCore
import RubyTransliteration
@testable import RubyUI
import SwiftUI
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

    @Test func romajiTakeTheEnvironmentsSystem() {
        #expect(RubyScript.romaji.resolved(.nippon).romanization == .nippon)
        #expect(RubyScript.romaji.romanization == .hepburn)
        // Kana scripts have no system to set.
        #expect(RubyScript.katakana.resolved(.nippon) == .katakana)
        #expect(RubyScript.hiragana(loanwords: .hiragana).resolved(.passport) == .hiragana(loanwords: .hiragana))
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
                baseWidth: { text, _ in CGFloat(text.count) },
                annotationWidth: { text, _ in CGFloat(text.count) / 2 }
            ).furigana.map(\.text)
        }
        #expect(furigana("東京で{本気|まじ}に{歩|ある}く", in: .katakana) == ["トウキョウ", "マジ", "アル"])
        #expect(furigana("東京で{本気|まじ}に{歩|ある}く", in: .romaji) == ["tōkyō", "maji", "aru"])
        #expect(furigana("東京で{本気|まじ}に{歩|ある}く", in: RubyScript.romaji.resolved(.nippon)) == ["tôkyô", "mazi", "aru"])
        // In hiragana, markup readings keep their kana, unless everything
        // is asked for in hiragana.
        #expect(furigana("{本気|マジ}で東京") == ["マジ", "とうきょう"])
        #expect(furigana("{本気|マジ}で東京", in: .hiragana(loanwords: .hiragana)) == ["まじ", "とうきょう"])
    }

    /// Word colorings say which color they give, for keys to the colors.
    @Test func wordColorsSayTheirColors() {
        #expect(RubyWordColors.partOfSpeech.color(for: .verb) == .red)
        #expect(RubyWordColors.jlpt.color(for: .n5) == .green)
        #expect(RubyWordColors.readingSources.color(for: .model) == .green)
        // Only levels a learner doesn't know yet.
        #expect(RubyWordColors.jlpt(above: .n4).color(for: .n4) == nil)
        #expect(RubyWordColors.jlpt(above: .n4).color(for: .n3) == .purple)
        // Colorings by something else have none.
        #expect(RubyWordColors.alternating.color(for: .verb) == nil)
    }
}
#endif
