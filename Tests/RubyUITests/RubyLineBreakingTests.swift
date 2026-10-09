import CoreText
import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Lines break between phrases in every font, including Dynamic Type text
/// styles, which would otherwise break between almost any two characters.
@MainActor @Suite struct RubyLineBreakingTests {
    private static let sentence = "今日は東京へ行きたい。コーヒーを飲みながら日本語を勉強しています。"

    private static let fonts: [Font] = [
        .body, .title3, .title3.bold(), .title3.italic(), .largeTitle,
        .system(.title3, design: .rounded), .system(.body, design: .serif),
        .system(size: 20), .custom("HiraginoSans-W3", size: 20, relativeTo: .body),
    ]

    @Test(arguments: fonts)
    func fontLooksTheSame(_ font: Font) throws {
        let original = font.resolve(in: try Self.fontContext()).ctFont
        let converted = RubyMetrics.phraseBreaking(original)
        #expect(Self.width(of: "今日はAbc123東京へ", in: converted) == Self.width(of: "今日はAbc123東京へ", in: original))
        #expect(CTFontGetSize(converted) == CTFontGetSize(original))
    }

    @Test(arguments: fonts)
    func linesBreakBetweenPhrases(_ font: Font) throws {
        let resolved = RubyMetrics.phraseBreaking(font.resolve(in: try Self.fontContext()).ctFont)
        let converted = Font(resolved)
        var text = AttributedString(Self.sentence)
        text.languageIdentifier = RubyLineBreaking.words.languageIdentifier
        // From six characters a line, so every phrase fits on one.
        let size = CTFontGetSize(resolved)
        for width in stride(from: size * 6, through: size * 18, by: size) {
            let lines = Self.lines(of: Text(text).font(converted), width: width)
            #expect(lines.count > 1)
            for line in lines.dropFirst() {
                #expect(!["へ", "を", "す", "い。", "ら"].contains { line.hasPrefix($0) }, "\(width): \(lines)")
            }
        }
    }

    /// Without kanji, the system finds phrases poorly. Kana spaced
    /// between phrases breaks at phrase ends far more often than the same
    /// kana without spaces, and never before a small kana or ー.
    @Test func spacesBetweenPhrasesGuideLineBreaks() throws {
        let original = RubyContent.content(for: Self.sentence)
        let boundaries = RubySpacing.phrases.boundaries(in: original)
        let spaced = original.transcribed(to: .hiragana, spacedAt: boundaries)
        let unspaced = original.transcribed(to: .hiragana)
        let font = RubyMetrics.phraseBreaking(Font.title3.resolve(in: try Self.fontContext()).ctFont)

        /// The share of line breaks at the end of a phrase: at `ends`, or
        /// after punctuation.
        func phraseShare(_ content: RubyContent, ends: Set<Int>) -> Double {
            var text = AttributedString(content.string)
            text.languageIdentifier = RubyLineBreaking.words.languageIdentifier
            let size = CTFontGetSize(font)
            var atEnds = 0
            var total = 0
            for width in stride(from: size * 6, through: size * 18, by: size / 2) {
                let lines = Self.lines(of: Text(text).font(Font(font)), width: width, string: content.string)
                var offset = 0
                for (line, next) in zip(lines, lines.dropFirst()) {
                    offset += line.utf16.count
                    total += 1
                    if ends.contains(offset) || line.hasSuffix("。") { atEnds += 1 }
                    #expect(next.first.map { !"ーぁぃぅぇぉゃゅょっ".contains($0) } ?? true, "\(width): \(lines)")
                }
            }
            return Double(atEnds) / Double(max(total, 1))
        }

        let withSpaces = phraseShare(spaced, ends: Set(spaced.spaces.map { $0 + 1 }))
        let withoutSpaces = phraseShare(unspaced, ends: Set(boundaries.map(unspaced.offset(fromOriginal:))))
        #expect(withSpaces > 0.6, "\(withSpaces)")
        #expect(withSpaces > withoutSpaces * 1.5, "\(withSpaces) with spaces, \(withoutSpaces) without")
    }

    // MARK: Helpers

    nonisolated(unsafe) private static var capturedContext: Font.Context?
    nonisolated(unsafe) private static var recordedLines: [String] = []

    private struct ContextCapture: View {
        @Environment(\.fontResolutionContext) private var context
        var body: some View {
            RubyLineBreakingTests.capturedContext = context
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Records the text of each line SwiftUI lays out.
    private struct LineRecorder: TextRenderer {
        let string: String
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            let utf16 = Array(string.utf16)
            var start: Text.Layout.CharacterIndex?
            RubyLineBreakingTests.recordedLines = layout.compactMap { line in
                let indices = line.flatMap(\.characterIndices)
                guard let lower = indices.min(), let upper = indices.max() else { return nil }
                if start == nil { start = lower }
                let range = start!.distance(to: lower)...start!.distance(to: upper)
                return String(utf16CodeUnits: Array(utf16[range]), count: range.count)
            }
        }
    }

    private static func fontContext() throws -> Font.Context {
        _ = ImageRenderer(content: ContextCapture()).uiImage
        return try #require(capturedContext)
    }

    private static func lines(of text: Text, width: CGFloat, string: String = sentence) -> [String] {
        recordedLines = []
        let view = text.textRenderer(LineRecorder(string: string)).frame(width: width, alignment: .leading)
        _ = ImageRenderer(content: view).uiImage
        return recordedLines
    }

    private static func width(of string: String, in font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
}
