import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Text from segments breaks lines between the phrases they give, never
/// inside one, with word joiners the content doesn't have.
@MainActor @Suite struct RubyGivenPhraseBreakingTests {
    /// 晩ご飯は寿司でした。森さん、ありがとうございました！ as an app gives
    /// it: a word per token, and phrases where words don't attach. The
    /// system's own phrases split ありがとうござ / いました and 森 / さん.
    private static let segments = [
        RubySegment("晩", reading: "ばん", word: .init(attachesToPrevious: false), wordID: "0"),
        RubySegment("ご", wordID: "0"),
        RubySegment("飯", reading: "はん", wordID: "0"),
        RubySegment("は", word: .init(attachesToPrevious: true), wordID: "1"),
        RubySegment("寿司", reading: "すし", word: .init(attachesToPrevious: false), wordID: "2"),
        RubySegment("でした", word: .init(attachesToPrevious: true), wordID: "3"),
        RubySegment("。", source: .dictionary),
        RubySegment("森", reading: "もり", word: .init(attachesToPrevious: false), wordID: "5"),
        RubySegment("さん", word: .init(attachesToPrevious: true), wordID: "6"),
        RubySegment("、", source: .dictionary),
        RubySegment("ありがとうございました", word: .init(attachesToPrevious: false), wordID: "8"),
        RubySegment("！", source: .dictionary),
    ]
    private static let content = RubyContent.content(for: segments)
    private static let phrases = ["晩ご飯は", "寿司でした", "森さん", "ありがとうございました"]

    private static func text(_ range: Range<Int>, of string: String) -> String {
        let utf16 = Array(string.utf16)
        return String(utf16CodeUnits: Array(utf16[range]), count: range.count)
    }

    // MARK: Joiners

    @Test func joinersGoInsideEachGivenPhrase() {
        let joiners = RubyLineBreaking.phrases.joiners(in: Self.content)
        #expect(Self.content.readingUnits.map { Self.text($0.range, of: Self.content.string) } == Self.phrases)
        // One between each two characters of a phrase, none between them.
        #expect(joiners.offsets.count == Self.phrases.reduce(0) { $0 + $1.count - 1 })
        let joined = String(joiners.inserted(into: AttributedString(Self.content.string)).characters)
        let pieces = joined.split(separator: "\u{2060}", omittingEmptySubsequences: false).map(String.init)
        #expect(pieces.first == "晩")
        #expect(joined.contains("ご\u{2060}飯\u{2060}は寿"))
        #expect(joined.contains("た。森\u{2060}さ\u{2060}ん、あ"))
        #expect(joined.replacingOccurrences(of: "\u{2060}", with: "") == Self.content.string)
    }

    @Test func onlyGivenPhrasesAreJoined() {
        // An analyzer's phrases, or none, are the system's to break.
        #expect(RubyLineBreaking.phrases.joiners(in: RubyContent.content(for: "森さん、ありがとうございました！")).isEmpty)
        #expect(RubyLineBreaking.anywhere.joiners(in: Self.content).isEmpty)
        #expect(RubyLineBreaking.phrases.joiners(in: Self.content, characterBreaking: [0]).isEmpty)
    }

    @Test func widePhrasesJoinOnlyTheirWords() {
        let morisan = Self.content.readingUnits[2].range
        let words = Self.content.words.map(\.range).filter { morisan.contains($0.lowerBound) }
        #expect(words.map { Self.text($0, of: Self.content.string) } == ["森", "さん"])
        let joiners = RubyLineBreaking.phrases.joiners(in: Self.content, widePhrases: [morisan])
        let joined = String(joiners.inserted(into: AttributedString(Self.content.string)).characters)
        #expect(joined.contains("。森さ\u{2060}ん、"))
        // A wide word breaks between its morphemes, two letters or more
        // from either end.
        let arigatou = Self.content.readingUnits[3].range
        let wide = RubyLineBreaking.phrases.joiners(in: Self.content, widePhrases: [arigatou], wideWords: [arigatou])
        let wideText = String(wide.inserted(into: AttributedString(Self.content.string)).characters)
        #expect(wideText.hasSuffix("あ\u{2060}り\u{2060}が\u{2060}と\u{2060}うご\u{2060}ざ\u{2060}いま\u{2060}し\u{2060}た！"), "\(wideText.replacingOccurrences(of: "\u{2060}", with: "·"))")
    }

    @Test func offsetsMoveBothWays() {
        let joiners = RubyLineBreaking.phrases.joiners(in: Self.content)
        let string = Self.content.string
        let joined = String(joiners.inserted(into: AttributedString(string)).characters)
        let joinedUTF16 = Array(joined.utf16)
        for offset in 0..<string.utf16.count {
            let moved = joiners.joinedOffset(offset)
            #expect(joinedUTF16[moved] == Array(string.utf16)[offset])
            #expect(joiners.originalOffset(moved) == offset)
        }
        // A joiner counts as the character after it.
        #expect(joiners.originalOffset(joiners.joinedOffset(1) - 1) == 1)
        // A range takes the joiners inside it, not those around it.
        for unit in Self.content.readingUnits {
            let range = joiners.joinedRange(unit.range)
            #expect(Self.text(range, of: joined).replacingOccurrences(of: "\u{2060}", with: "") == Self.text(unit.range, of: string))
            #expect(!Self.text(range, of: joined).hasPrefix("\u{2060}") && !Self.text(range, of: joined).hasSuffix("\u{2060}"))
        }
        #expect(joiners.joinedRange(3..<3).isEmpty)
    }

    @Test func joinersAddNoSpaceAndKeepTheLanguage() {
        var text = AttributedString(Self.content.string)
        text.languageIdentifier = "ja-u-lb-strict"
        text[text.characters.index(text.startIndex, offsetBy: 1)..<text.characters.index(text.startIndex, offsetBy: 2)].tracking = 3
        let joined = RubyLineBreaking.phrases.joiners(in: Self.content).inserted(into: text)
        for run in joined.runs where String(joined[run.range].characters).contains("\u{2060}") {
            #expect(run.languageIdentifier == "ja-u-lb-strict")
            #expect(run.tracking == nil)
        }
    }

    @Test func spokenTextMovesWithTheJoiners() {
        let joiners = RubyLineBreaking.phrases.joiners(in: Self.content)
        // 森, said もり.
        let mori = RubySpokenText(range: 10..<11, text: "もり")
        let moved = joiners.moved([mori, RubySpokenText(pauseAt: 0..<4)])
        #expect(moved[0].range == joiners.joinedRange(10..<11))
        #expect(moved[0].text == "もり")
        #expect(moved[1].isPause && moved[1].range == joiners.joinedRange(0..<4))
    }

    // MARK: Layout

    @Test func annotationsStayOnTheirCharacters() throws {
        let metrics = RubyMetrics(font: .system(size: 24), in: try Self.fontContext())
        let layout = Self.layout(metrics: metrics, joiners: RubyLineBreaking.phrases.joiners(in: Self.content))
        let joined = String(layout.text.characters)
        let readings = layout.paragraphs[0].furigana.map { (Self.text($0.range, of: joined), $0.text) }
        #expect(readings.map(\.0) == ["晩", "飯", "寿\u{2060}司", "森"])
        #expect(readings.map(\.1) == ["ばん", "はん", "すし", "もり"])
        // And a tap on a character finds it in the content.
        for offset in 0..<joined.utf16.count where Array(joined.utf16)[offset] != 0x2060 {
            let original = layout.offset(offset, inParagraph: 0)
            #expect(Array(Self.content.string.utf16)[original] == Array(joined.utf16)[offset])
        }
    }

    /// From a line as wide as the longest phrase, every line starts at a
    /// phrase; narrower, a wide phrase breaks between its words, and a
    /// wide word between the system's phrases, as `RubyText` lays them out
    /// again.
    @Test func linesBreakBetweenGivenPhrases() throws {
        let metrics = RubyMetrics(font: .system(size: 24), in: try Self.fontContext())
        let string = Self.content.string
        let phraseStarts = Set(Self.content.readingUnits.map(\.range.lowerBound))
        let afterPunctuation = Set(string.utf16.indices.compactMap { index -> Int? in
            let offset = string.utf16.distance(from: string.utf16.startIndex, to: index)
            return "。、！".utf16.contains(string.utf16[index]) ? offset + 1 : nil
        })
        let longest = metrics.baseWidth(of: "ありがとうございました！")
        var foundWide = 0
        for width in stride(from: metrics.fontSize * 4, through: metrics.fontSize * 20, by: metrics.fontSize / 2) {
            var widePhrases: Set<Range<Int>> = []
            var wideWords: Set<Range<Int>> = []
            var starts: [Int] = []
            // Laid out again until nothing new is found, as RubyText does.
            for _ in 0..<3 {
                let joiners = RubyLineBreaking.phrases.joiners(in: Self.content, widePhrases: widePhrases, wideWords: wideWords)
                let layout = Self.layout(metrics: metrics, joiners: joiners)
                let lineStarts = joiners.originalLineStarts(Self.lineStarts(of: layout, width: width, metrics: metrics), paragraphStarts: [0])
                starts = lineStarts.map(\.offset)
                let found = RubyLineBreaking.findWide(
                    in: string, lineStarts: lineStarts, paragraphStarts: [0],
                    phrases: Self.content.readingUnits.map(\.range), words: Self.content.words.map(\.range),
                    characterBreaking: [], widePhrases: &widePhrases, wideWords: &wideWords
                )
                if !found { break }
                foundWide += 1
            }
            if width >= longest + metrics.fontSize {
                for start in starts.dropFirst() {
                    #expect(phraseStarts.contains(start) || afterPunctuation.contains(start), "\(width): \(starts)")
                }
            }
            // Never ございまし / た！, nor a line that starts with ！.
            #expect(!starts.contains(Self.content.string.utf16.count - 2), "\(width): \(starts)")
            #expect(!starts.contains(Self.content.string.utf16.count - 1), "\(width): \(starts)")
        }
        #expect(foundWide > 0)
    }

    // MARK: Helpers

    private static func layout(metrics: RubyMetrics, joiners: RubyWordJoiners) -> RubyLayout {
        let measurements = RubyMeasurements.measurements(for: content, metrics: metrics, furiganaScript: .hiragana, romanization: .hepburn)
        return RubyLayout(
            measurements: measurements, furigana: 1, romaji: 0,
            readingVisibility: .zero, romajiVisibility: .zero, wordGaps: .zero,
            fontSize: metrics.fontSize, romajiSpacing: metrics.romajiSpacing,
            lineBreaking: .phrases, joiners: joiners,
            insertedSpaceWidth: 0, textColors: [], backgrounds: []
        )
    }

    nonisolated(unsafe) private static var capturedContext: Font.Context?
    nonisolated(unsafe) private static var recordedStarts: [(paragraph: Int, offset: Int)] = []

    private struct ContextCapture: View {
        @Environment(\.fontResolutionContext) private var context
        var body: some View {
            RubyGivenPhraseBreakingTests.capturedContext = context
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private static func fontContext() throws -> Font.Context {
        _ = ImageRenderer(content: ContextCapture()).cgImage
        return try #require(capturedContext)
    }

    /// Records where each line starts in the laid-out text.
    private struct LineStartRecorder: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            RubyGivenPhraseBreakingTests.recordedStarts = layout.rubyParagraphLines.compactMap { _, line, paragraph, start in
                line.flatMap(\.characterIndices).min().map { (paragraph, start.distance(to: $0)) }
            }
        }
    }

    private static func lineStarts(of layout: RubyLayout, width: CGFloat, metrics: RubyMetrics) -> [(paragraph: Int, offset: Int)] {
        recordedStarts = []
        let view = Text(layout.text).font(metrics.textFont).textRenderer(LineStartRecorder()).frame(width: width, alignment: .leading)
        _ = ImageRenderer(content: view).cgImage
        return recordedStarts
    }
}
