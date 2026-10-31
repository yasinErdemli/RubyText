import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Words shown as blanks to fill, such as the gap in an exercise.
@MainActor
@Suite struct RubyBlankTests {
    /// テレビを見ました, with を, the particle to fill in, as its own word,
    /// and 見ました in pieces.
    private static let segments = [
        RubySegment("テレビ", wordID: "terebi"),
        RubySegment("を", word: .init(attachesToPrevious: true), wordID: "gap"),
        RubySegment("見", reading: "み", word: .init(attachesToPrevious: false), wordID: "mimashita"),
        RubySegment("ました", wordID: "mimashita"),
    ]
    private static let content = RubyContent.content(for: segments)

    /// The text each blank stands in for.
    private func blanked(_ blanks: RubyBlanks, in content: RubyContent = content) -> [String] {
        blanks.ranges(in: content).map { RubyReadingUnits.substring(of: content.string, utf16Range: $0) }
    }

    /// A word in pieces is one blank, and so are neighboring chosen words.
    @Test func blanksAreChosenWords() {
        #expect(blanked(.wordIDs(["gap"])) == ["を"])
        #expect(blanked(.wordIDs(["mimashita"])) == ["見ました"])
        #expect(blanked(.wordIDs(["gap", "mimashita"])) == ["を見ました"])
        #expect(blanked(.wordIDs(["terebi", "mimashita"])) == ["テレビ", "見ました"])
        #expect(blanked(.wordIDs([])) == [])
    }

    /// VoiceOver pauses at a blank instead of saying its words or their
    /// readings, and says the rest as before.
    @Test func voiceOverPausesAtABlank() {
        let speech = [RubySpokenText(range: 4..<5, text: "み"), RubySpokenText(range: 0..<3, text: "テレビ")]
        let paused = RubyText.speech(speech, pausingAt: [3..<8])
        #expect(paused.map(\.range) == [0..<3, 3..<8])
        #expect(paused.map(\.isPause) == [false, true])
        #expect(paused.last?.ssml.contains("<break") == true)
        #expect(paused.last?.text == "")
        #expect(RubyText.speech(speech, pausingAt: []) == speech)
    }

    /// Each blank is placed in its paragraph, to be drawn there.
    @Test func blanksAreLaidOutInTheirParagraphs() {
        let content = RubyContent.content(for: [RubySegment("はい\n", wordID: "hai"), RubySegment("を", wordID: "gap")])
        let blanks = RubyBlanks.wordIDs(["gap"]).ranges(in: content)
        let layout = RubyLayout(
            measurements: RubyMeasurements(
                content: content,
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
            textColors: [],
            backgrounds: [],
            blanks: blanks
        )
        #expect(layout.paragraphs.map(\.blanks) == [[], [0..<1]])
    }

    /// A blank keeps its words' place and the room their readings and
    /// romaji take, so nothing moves when they fill it.
    @Test func aBlankTakesItsWordsRoom() {
        for style: RubyStyle in [.furigana, [.furigana, .kanaRomaji]] {
            let filled = Self.size(of: RubyText(segments: Self.segments).rubyStyle(style))
            let blank = Self.size(of: RubyText(segments: Self.segments).rubyStyle(style).rubyBlanks(.wordIDs(["mimashita"])))
            #expect(blank == filled)
        }
    }

    /// A blank's words and their readings aren't drawn; a box in the tint
    /// color is, in their place.
    @Test func aBlankIsAnEmptyBox() throws {
        let segments = [RubySegment("見", reading: "み", wordID: "gap")]
        let filled = try Self.colors(in: RubyText(segments: segments))
        #expect(filled.dark > 0)
        let blank = try Self.colors(in: RubyText(segments: segments).rubyBlanks(.wordIDs(["gap"])))
        #expect(blank.dark == 0)
        #expect(blank.tinted > 0)
    }

    /// The size `text` takes in 20-point type, 300 points wide.
    private static func size(of text: some View) -> CGSize {
        let renderer = ImageRenderer(content: text.font(.system(size: 20)).fixedSize())
        renderer.proposedSize = ProposedViewSize(width: 300, height: nil)
        return renderer.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    /// How many pixels of `text`, black on white in red's tint, are dark,
    /// as text is, and how many are reddish, as a blank's box is.
    private static func colors(in text: some View) throws -> (dark: Int, tinted: Int) {
        let renderer = ImageRenderer(content: text
            .font(.system(size: 40))
            .foregroundStyle(.black)
            .tint(.red)
            .padding(8)
            .background(.white))
        let image = try #require(renderer.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var dark = 0, tinted = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let (red, green, blue) = (Int(pixels[pixel]), Int(pixels[pixel + 1]), Int(pixels[pixel + 2]))
            if red < 80 && green < 80 && blue < 80 { dark += 1 }
            if red > green + 30 && red > blue + 30 { tinted += 1 }
        }
        return (dark, tinted)
    }
}
