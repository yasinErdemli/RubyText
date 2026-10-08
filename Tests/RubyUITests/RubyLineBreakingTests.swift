import CoreText
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

    private static func lines(of text: Text, width: CGFloat) -> [String] {
        recordedLines = []
        let view = text.textRenderer(LineRecorder(string: sentence)).frame(width: width, alignment: .leading)
        _ = ImageRenderer(content: view).uiImage
        return recordedLines
    }

    private static func width(of string: String, in font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
}
