import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Lines under chosen words, such as the words a tap explains.
@MainActor
@Suite struct RubyWordUnderlineTests {
    /// もりさんは食べ物を食べた, with もり and さん two words side by side, and
    /// 食べ物 in pieces.
    private static let content = RubyContent.content(for: [
        RubySegment("もり", wordID: "mori"),
        RubySegment("さん", word: .init(attachesToPrevious: true), wordID: "san"),
        RubySegment("は", word: .init(attachesToPrevious: true), wordID: "wa"),
        RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "food"),
        RubySegment("べ", wordID: "food"),
        RubySegment("物", reading: "もの", wordID: "food"),
        RubySegment("を", word: .init(attachesToPrevious: true), wordID: "o"),
        RubySegment("食", reading: "た", word: .init(attachesToPrevious: false), wordID: "eat"),
        RubySegment("べた", wordID: "eat"),
    ])

    /// The text each line is under.
    private func underlined(_ underlines: RubyWordUnderlines, in content: RubyContent = content) -> [String] {
        underlines.ranges(in: content).map { RubyReadingUnits.substring(of: content.string, utf16Range: $0) }
    }

    /// Neighboring words get lines of their own, so they read as two, and
    /// a word given in pieces gets one.
    @Test func eachWordGetsALineOfItsOwn() {
        #expect(underlined(.wordIDs(["mori", "san", "food"])) == ["もり", "さん", "食べ物"])
        #expect(underlined(.wordIDs(["eat"])) == ["食べた"])
        #expect(underlined(.wordIDs([])) == [])
    }

    /// Chosen as written, a verb is underlined with its endings, and a run
    /// of words matched together gets one line.
    @Test func wordsAreMatchedAsColorsMatchThem() {
        let verb = RubyContent.content(for: [
            RubySegment("生まれ", word: .init(partOfSpeech: .verb, dictionaryForm: "生まれる")),
            RubySegment("た", word: .init(partOfSpeech: .auxiliary, attachesToPrevious: true)),
        ])
        #expect(underlined(.words(["生まれる"]), in: verb) == ["生まれた"])
        #expect(underlined(.words(["もりさん", "物"])) == ["もりさん"])
    }

    @Test func dotsAreTheDefault() {
        #expect(RubyWordUnderlines.wordIDs(["mori"]).underlines(in: Self.content).map(\.pattern) == [.dotted])
        #expect(RubyWordUnderlines.words(["食べ物"], pattern: .dashed).underlines(in: Self.content).map(\.pattern) == [.dashed])
        #expect(RubyWordUnderlines.wordIDs(["mori"]) != .wordIDs(["mori"], pattern: .solid))
    }

    /// Words can have lines of their own kinds, such as dots under words
    /// a tap explains and a solid line under a gap to fill.
    @Test func wordsCanHaveTheirOwnKindOfLine() {
        let byID = RubyWordUnderlines.wordIDs(["mori": .dotted, "food": .solid, "eat": .dashed])
        #expect(byID.underlines(in: Self.content).map(\.pattern) == [.dotted, .solid, .dashed])
        #expect(underlined(byID) == ["もり", "食べ物", "食べた"])
        let byWord = RubyWordUnderlines.words(["もりさん": .solid, "食べ物": .dotted])
        #expect(byWord.underlines(in: Self.content).map(\.pattern) == [.solid, .dotted])
        #expect(byID == .wordIDs(["mori": .dotted, "food": .solid, "eat": .dashed]))
        #expect(RubyWordUnderlines.wordIDs(["mori": .solid]) == .wordIDs(["mori"], pattern: .solid))
    }

    /// Each line keeps its kind as it's laid out, to be drawn that way.
    @Test func linesKeepTheirKind() {
        let underlines = RubyWordUnderlines.wordIDs(["mori": .dotted, "food": .solid]).underlines(in: Self.content)
        let layout = Self.layout(underlines: underlines)
        #expect(layout.paragraphs.flatMap(\.underlines).map(\.pattern) == [.dotted, .solid])
    }

    /// A line takes its word's color, to draw it in.
    @Test func linesTakeTheirWordsColor() {
        let underlines = RubyWordUnderlines.wordIDs(["mori", "food"]).underlines(in: Self.content)
        let ranges = underlines.map(\.range)
        let laidOut = Self.layout(underlines: underlines, textColors: [RubyColoredRange(range: ranges[1], color: .red)])
            .paragraphs.flatMap(\.underlines)
        #expect(laidOut.map(\.range) == ranges)
        #expect(laidOut.map(\.color) == [nil, .red])
    }

    /// The test content laid out with `underlines` and `textColors`.
    private static func layout(underlines: [RubyUnderline], textColors: [RubyColoredRange] = []) -> RubyLayout {
        RubyLayout(
            measurements: RubyMeasurements(
                content: Self.content,
                baseWidth: { text, _ in CGFloat(text.count) },
                annotationWidth: { text, _ in CGFloat(text.count) / 2 }
            ),
            furigana: 1,
            romaji: 0,
            readingVisibility: .zero,
            romajiVisibility: .zero,
            wordGaps: .zero,
            fontSize: 1,
            romajiSpacing: 0,
            lineBreaking: .phrases,
            insertedSpaceWidth: 0,
            textColors: textColors,
            backgrounds: [],
            underlines: underlines
        )
    }

    /// Underlined text keeps room below each line for the lines, so they
    /// don't touch the text or the furigana of the next line.
    @Test func underlinedTextIsTaller() {
        let segments: [RubySegment] = [
            RubySegment("大学", reading: "だいがく", wordID: "daigaku"),
            RubySegment("です", wordID: "desu"),
        ]
        let plain = Self.size(of: RubyText(segments: segments))
        let underlined = Self.size(of: RubyText(segments: segments).rubyWordUnderlines(.wordIDs(["daigaku"])))
        let none = Self.size(of: RubyText(segments: segments).rubyWordUnderlines(.wordIDs(["nothing"])))
        let metrics = RubyMetrics(font: .system(size: 20), in: EnvironmentValues().fontResolutionContext)
        #expect(underlined.height == plain.height + metrics.underlineSpace)
        #expect(none == plain)
    }

    /// The size `text` takes in 20-point type, 300 points wide.
    private static func size(of text: some View) -> CGSize {
        let log = Measuring.Log()
        let renderer = ImageRenderer(content: Measuring(log: log) { text.font(.system(size: 20)) })
        renderer.proposedSize = ProposedViewSize(width: 300, height: nil)
        _ = renderer.cgImage
        return log.size ?? .zero
    }
}

/// Notes the size its view takes.
private struct Measuring: Layout {
    let log: Log

    final class Log: @unchecked Sendable {
        var size: CGSize?
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        log.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
