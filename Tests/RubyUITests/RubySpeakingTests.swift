import Accessibility
import RubyCore
@testable import RubyUI
import Testing

/// SSML on the text VoiceOver reads.
@Suite struct RubySpeakingTests {
    /// Each run of `text` with its SSML.
    private func runs(_ text: AttributedString) -> [(String, String?)] {
        text.runs[\.accessibilitySpeechSSML].map { ssml, range in (String(text[range].characters), ssml) }
    }

    @Test func ssmlCoversItsRange() {
        var text = AttributedString("宇宙を見た")
        text.languageIdentifier = "ja"
        let spoken = text.speaking([RubySpokenText(range: 0..<2, text: "そら"), RubySpokenText(range: 3..<4, text: "み")])
        #expect(runs(spoken).map(\.0) == ["宇宙", "を", "見", "た"])
        #expect(runs(spoken).map(\.1) == ["そら", nil, "み", nil])
        // Other attributes stay.
        #expect(spoken.runs.allSatisfy { $0.languageIdentifier == "ja" })
    }

    @Test func rangesAreUTF16() {
        // 𠮷 is two UTF-16 units, so 𠮷野家 is four.
        let spoken = AttributedString("𠮷野家に行く").speaking([RubySpokenText(range: 0..<4, text: "よしのや")])
        #expect(runs(spoken).map(\.0) == ["𠮷野家", "に行く"])
    }

    @Test func noSpeechLeavesTheText() {
        let text = AttributedString("今日は")
        #expect(text.speaking([]) == text)
    }
}
