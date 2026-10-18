import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// How tall `RubyText` is where it's offered less height than its lines
/// need, as in a stack that has run out of room.
@MainActor
@Suite struct RubyHeightTests {
    /// Three phrases that wrap onto lines of their own at `width`.
    private static let segments: [RubySegment] = [
        RubySegment("わたし", wordID: "0"),
        RubySegment("は", wordID: "1"),
        RubySegment("大学", reading: "だいがく", wordID: "2"),
        RubySegment("の", wordID: "3"),
        RubySegment("先生", reading: "せんせい", wordID: "4"),
        RubySegment("です", wordID: "5"),
        RubySegment("。"),
        RubySegment("どうぞ", wordID: "6"),
        RubySegment("よろしく", wordID: "7"),
        RubySegment("おねがいします", wordID: "8"),
        RubySegment("。"),
    ]
    private static let width: CGFloat = 200

    /// The text with furigana, with furigana and romaji under its kana,
    /// with underlined words above romaji, with no annotations but tappable
    /// words, and plain, which is drawn without a renderer.
    enum Kind: CaseIterable {
        case furigana, kanaRomaji, underlined, tappable, plain

        var text: some View {
            let text = RubyText(segments: RubyHeightTests.segments)
            return Group {
                switch self {
                case .furigana: text
                case .kanaRomaji: text.rubyStyle([.furigana, .kanaRomaji])
                case .underlined: text.rubyStyle([.furigana, .kanaRomaji]).rubyWordUnderlines(.wordIDs(["2", "4", "8"]))
                case .tappable: text.rubyStyle([]).onRubyWordTap { _ in }.rubyWordDetails(false)
                case .plain: text.rubyStyle([])
                }
            }
            .font(.system(size: 20))
        }
    }

    @Test(arguments: Kind.allCases)
    func wrappedTextTakesTheHeightItsLinesNeed(_ kind: Kind) {
        let whole = Self.size(of: kind.text, offered: nil)
        // Wrapped onto three lines at least.
        #expect(whole.height > 60)
        for height in [0, 30, whole.height / 2, whole.height - 1] {
            #expect(Self.size(of: kind.text, offered: height) == whole, "offered \(height)")
        }
    }

    /// Offered less height, the text used to answer with the lines that fit
    /// but draw one more below them, as the room it has around it to draw
    /// annotations in let one more in: chat bubbles had their second line
    /// drawn over the next bubble.
    @Test(arguments: Kind.allCases)
    func nothingIsDrawnBelowTheText(_ kind: Kind) throws {
        for height: CGFloat in [0, 30, 60] {
            let log = Offering.Log()
            let renderer = ImageRenderer(content: Offering(height: height, log: log) { kind.text }
                // Room below the text, to see whether anything is drawn there.
                .padding(.bottom, 200))
            renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
            let image = try #require(renderer.cgImage)
            let size = try #require(log.size)
            // A row of antialiasing below the last line is fine.
            let inkBelow = try Self.lastRowWithInk(in: image).map { CGFloat($0) > size.height.rounded(.up) + 1 } ?? false
            #expect(!inkBelow, "offered \(height): \(size)")
        }
    }

    @Test func lineLimitStillCutsTheTextShort() {
        let text = RubyText(segments: Self.segments).font(.system(size: 20))
        let whole = Self.size(of: text, offered: nil)
        let oneLine = Self.size(of: text.lineLimit(1), offered: nil)
        #expect(oneLine.height < whole.height / 2)
        #expect(Self.size(of: text.lineLimit(1), offered: 0) == oneLine)
    }

    /// The size `view` takes `width` wide, offered `height`.
    private static func size(of view: some View, offered height: CGFloat?) -> CGSize {
        let log = Offering.Log()
        let renderer = ImageRenderer(content: Offering(height: height, log: log) { view })
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        _ = renderer.cgImage
        return log.size ?? .zero
    }

    /// The last row of `image`, from the top, with anything drawn in it.
    private static func lastRowWithInk(in image: CGImage) throws -> Int? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The context's rows start at the top of the image.
        return (0..<height).last { row in
            (0..<width).contains { pixels[(row * width + $0) * 4 + 3] > 0 }
        }
    }
}

/// Offers its view the width it's offered and a height of its own, as a
/// stack that has run out of room does, and notes the size the view takes.
private struct Offering: Layout {
    let height: CGFloat?
    let log: Log

    final class Log: @unchecked Sendable {
        var size: CGSize?
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: height))
        log.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: height))
    }
}
