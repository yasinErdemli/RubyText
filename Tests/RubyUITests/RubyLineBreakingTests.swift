// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import CoreText
import RubyCore
import RubyTransliteration
@testable import RubyUI
import SwiftUI
import Testing

/// Lines break between phrases in every font, including Dynamic Type text
/// styles, which would otherwise break between almost any two characters.
@MainActor @Suite struct RubyLineBreakingTests {
    private static let sentence = "今日は東京へ行きたい。コーヒーを飲みながら日本語を勉強しています。"

    // Test arguments are read off the main actor.
    nonisolated private static let fonts: [Font] = [
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
        text.languageIdentifier = RubyLineBreaking.phrases.languageIdentifier
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

    /// Words set bold are measured, set and annotated in the bold font,
    /// which still breaks lines between phrases.
    @Test func boldWordsBreakBetweenPhrases() throws {
        let metrics = RubyMetrics(font: .title3, in: try Self.fontContext())
        let content = RubyContent.content(for: Self.sentence)
        // 東京へ行きたい
        let weights = [RubyWeightedRange(range: 3..<10, weight: .bold)]
        let measurements = RubyMeasurements.measurements(
            for: content, metrics: metrics, furiganaScript: .hiragana, romanization: .hepburn, weights: weights
        )
        let layout = RubyLayout(
            measurements: measurements, furigana: 1, romaji: 0,
            readingVisibility: .zero, romajiVisibility: .zero, wordGaps: .zero,
            fontSize: metrics.fontSize, romajiSpacing: metrics.romajiSpacing,
            lineBreaking: .phrases, insertedSpaceWidth: 0, textColors: [], backgrounds: [],
            weightedMetrics: [.bold: metrics.weighted(.bold)]
        )
        let bold = layout.text.runs.filter { $0.font != nil }.map { String(layout.text[$0.range].characters) }.joined()
        #expect(bold == "東京へ行きたい")
        // 今日, 東京, 行, 飲, 日本語, 勉強
        #expect(layout.paragraphs[0].furigana.map { $0.font != nil } == [false, true, true, false, false, false])

        let size = metrics.fontSize
        for width in stride(from: size * 6, through: size * 18, by: size) {
            let lines = Self.lines(of: Text(layout.text).font(metrics.textFont), width: width)
            #expect(lines.count > 1)
            for line in lines.dropFirst() {
                #expect(!["へ", "を", "す", "い。", "ら"].contains { line.hasPrefix($0) }, "\(width): \(lines)")
            }
        }

        // Letters are wider bold, and measured so.
        let latin = RubyContent.content(for: "Wordを見た")
        let regular = RubyMeasurements(content: latin, baseWidth: { text, _ in metrics.baseWidth(of: text) }, annotationWidth: { _, _ in 0 })
        let heavy = RubyMeasurements.measurements(
            for: latin, metrics: metrics, furiganaScript: .hiragana, romanization: .hepburn,
            weights: [RubyWeightedRange(range: 0..<4, weight: .heavy)]
        )
        #expect(heavy.widths[0..<4].reduce(0, +) > regular.widths[0..<4].reduce(0, +))
        #expect(heavy.widths[4...] == regular.widths[4...])
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
            text.languageIdentifier = RubyLineBreaking.phrases.languageIdentifier
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

    @Test func endingsHoldTheLastWords() {
        func endings(_ string: String) -> [String] {
            let content = RubyContent.content(for: string)
            let utf16 = Array(content.string.utf16)
            return RubyLineBreaking.endings(in: content).map {
                String(utf16CodeUnits: Array(utf16[$0]), count: $0.count)
            }
        }
        #expect(endings("日本語を勉強しています。") == ["ます。"])
        // だ alone has one letter, so the word before it joins.
        #expect(endings("夏は夜が好きだ。") == ["好きだ。"])
        // Each takes its paragraph's line break.
        #expect(endings("春は桜がきれいだ。\n公園で花見をする人が多い。") == ["きれいだ。\n", "多い。"])
        #expect(endings("「はい」") == ["はい」"])
        // Paragraphs without letters have none.
        #expect(endings("。\n\n猫が好き") == ["好き"])
    }

    /// Breaking anywhere, the last line of a paragraph never holds a single
    /// kana (す。), with or without annotations.
    @Test(arguments: [RubyLineBreaking.phrases, .anywhere])
    func paragraphsNeverEndWithOneKana(_ lineBreaking: RubyLineBreaking) throws {
        let metrics = RubyMetrics(font: .title3, in: try Self.fontContext())
        let texts = [
            Self.sentence,
            "春は桜がきれいだ。公園で花見をする人が多い。\n夏は夜が好きだ。窓を開けると、涼しい風が入ってくる。",
            "侍の魂と志を胸に、暁の湖で雷を待つ。",
        ]
        for string in texts {
            let content = RubyContent.content(for: string)
            let measurements = RubyMeasurements.measurements(for: content, metrics: metrics, furiganaScript: .hiragana, romanization: .hepburn)
            for annotations in [CGFloat(0), 1] {
                let layout = RubyLayout(
                    measurements: measurements, furigana: annotations, romaji: annotations,
                    readingVisibility: .zero, romajiVisibility: .zero, wordGaps: .zero,
                    fontSize: metrics.fontSize, romajiSpacing: metrics.romajiSpacing,
                    lineBreaking: lineBreaking, insertedSpaceWidth: 0,
                    textColors: [], backgrounds: []
                )
                // From six characters a line, so the last words fit on one.
                for width in stride(from: metrics.fontSize * 6, through: metrics.fontSize * 20, by: metrics.fontSize / 4) {
                    let paragraphs = Self.paragraphLines(of: Text(layout.text).font(metrics.textFont), width: width, string: content.string)
                    #expect(paragraphs.count == string.count { $0 == "\n" } + 1)
                    for lines in paragraphs where lines.count > 1 {
                        let letters = lines[lines.count - 1].filter { !($0.isPunctuation || $0.isWhitespace) }
                        #expect(letters.count > 1, "\(lineBreaking) \(width): \(lines)")
                    }
                }
            }
        }
    }

    /// Text cut short draws an ellipsis in place of the first character it
    /// hides; annotations skip it.
    @Test(arguments: [Text.TruncationMode.tail, .middle, .head])
    func ellipsesAreFound(_ mode: Text.TruncationMode) throws {
        struct Recorder: TextRenderer {
            let mode: Text.TruncationMode
            func draw(layout: Text.Layout, in context: inout GraphicsContext) {
                guard layout.isTruncated, let ellipsis = RubyRenderer.ellipsis(in: layout, mode: mode) else { return }
                let base = layout[0].first!.characterIndices.first!
                let offsets = layout[ellipsis.line].flatMap(\.characterIndices).map { base.distance(to: $0) }
                RubyLineBreakingTests.recordedEllipsis = (offsets[ellipsis.glyph], offsets.enumerated().filter { $0.offset != ellipsis.glyph }.map(\.element))
            }
        }
        let metrics = RubyMetrics(font: .body, in: try Self.fontContext())
        let content = RubyContent.content(for: Self.sentence + Self.sentence)
        let measurements = RubyMeasurements.measurements(for: content, metrics: metrics, furiganaScript: .hiragana, romanization: .hepburn)
        let layout = RubyLayout(
            measurements: measurements, furigana: 1, romaji: 1,
            readingVisibility: .zero, romajiVisibility: .zero, wordGaps: .zero,
            fontSize: metrics.fontSize, romajiSpacing: metrics.romajiSpacing,
            lineBreaking: .phrases, insertedSpaceWidth: 0, textColors: [], backgrounds: []
        )
        Self.recordedEllipsis = nil
        let view = Text(layout.text).font(metrics.textFont).lineLimit(2).truncationMode(mode)
            .textRenderer(Recorder(mode: mode)).frame(width: 300)
        _ = ImageRenderer(content: view).cgImage
        let (ellipsis, shown) = try #require(Self.recordedEllipsis)
        // The ellipsis stands in for the first character hidden: after the
        // text shown, before it, or after its first part.
        switch mode {
        case .head: #expect(ellipsis < shown.min()!)
        case .middle:
            let firstPart = shown.prefix { $0 < ellipsis }
            #expect(ellipsis == firstPart.max()! + 1)
            #expect(shown.contains { $0 > ellipsis + 1 })
        default: #expect(ellipsis == shown.max()! + 1)
        }
    }

    // MARK: Helpers

    nonisolated(unsafe) private static var capturedContext: Font.Context?
    nonisolated(unsafe) private static var recordedLines: [String] = []
    nonisolated(unsafe) private static var recordedParagraphs: [[String]] = []
    nonisolated(unsafe) private static var recordedEllipsis: (offset: Int, shown: [Int])?

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

    /// Records the text of each line SwiftUI lays out, by paragraph.
    private struct ParagraphRecorder: TextRenderer {
        let string: String
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            let utf16 = Array(string.utf16)
            var paragraphStarts = [0]
            for (offset, unit) in utf16.enumerated() where unit == 0x0A { paragraphStarts.append(offset + 1) }
            var paragraphs = [[String]](repeating: [], count: paragraphStarts.count)
            for (_, line, paragraph, start) in layout.rubyParagraphLines {
                let indices = line.flatMap(\.characterIndices)
                guard let lower = indices.min(), let upper = indices.max() else { continue }
                let range = (paragraphStarts[paragraph] + start.distance(to: lower))...(paragraphStarts[paragraph] + start.distance(to: upper))
                paragraphs[paragraph].append(String(utf16CodeUnits: Array(utf16[range]), count: range.count))
            }
            RubyLineBreakingTests.recordedParagraphs = paragraphs
        }
    }

    private static func paragraphLines(of text: Text, width: CGFloat, string: String) -> [[String]] {
        recordedParagraphs = []
        let view = text.textRenderer(ParagraphRecorder(string: string)).frame(width: width, alignment: .leading)
        _ = ImageRenderer(content: view).cgImage
        return recordedParagraphs
    }

    private static func fontContext() throws -> Font.Context {
        _ = ImageRenderer(content: ContextCapture()).cgImage
        return try #require(capturedContext)
    }

    private static func lines(of text: Text, width: CGFloat, string: String = sentence) -> [String] {
        recordedLines = []
        let view = text.textRenderer(LineRecorder(string: string)).frame(width: width, alignment: .leading)
        _ = ImageRenderer(content: view).cgImage
        return recordedLines
    }

    private static func width(of string: String, in font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.init(kCTFontAttributeName as String): font])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
}
#endif
