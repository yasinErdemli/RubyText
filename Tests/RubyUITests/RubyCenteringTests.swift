import RubyCore
@testable import RubyUI
import SwiftUI
import Testing

/// Readings wider than their base stay centered over it, even where the
/// base starts or ends its paragraph.
@MainActor
@Suite struct RubyCenteringTests {
    /// A word on its own, as on a flashcard, used to show its reading
    /// starting with it and running off to the right.
    @Test(arguments: ["私|わたし", "私|わたくし", "侍|さむらい"])
    func aWordOnItsOwnSitsUnderTheMiddleOfItsReading(_ markup: String) throws {
        let parts = markup.split(separator: "|").map(String.init)
        let text = RubyText(segments: [RubySegment(parts[0], reading: parts[1])])
            .font(.system(size: 40))
            .fixedSize()
        let renderer = ImageRenderer(content: text)
        let image = try #require(renderer.cgImage)
        let bands = try Self.inkColumns(in: image)
        try #require(bands.count == 2)
        let (reading, base) = (bands[0], bands[1])
        // Within a pixel or two of antialiasing.
        #expect(abs(reading.mid - base.mid) <= 2, "reading \(reading), base \(base)")
        // And all of the reading is inside the view.
        #expect(reading.lowerBound > 0)
        #expect(reading.upperBound < image.width - 1)
    }

    /// Romaji wider than the word and its reading, as under 私 for a
    /// learner who can't read わたし yet, used to start with it too.
    /// Whether they're the kana romaji of its reading or romaji for the
    /// whole word.
    @Test(arguments: [true, false])
    func aWordOnItsOwnSitsOverTheMiddleOfItsRomaji(kanaRomaji: Bool) throws {
        // Padded, so romaji running past the view still show, but the
        // padding is clear, so its ink shows how wide the view is.
        let padding = 40
        let text = RubyText(segments: [RubySegment("私", reading: "わたし")])
            .rubyStyle(kanaRomaji ? [.furigana, .kanaRomaji] : [.furigana, .romaji])
            .font(.system(size: 40))
            .fixedSize()
            .padding(CGFloat(padding))
        let renderer = ImageRenderer(content: text)
        let image = try #require(renderer.cgImage)
        let bands = try Self.inkColumns(in: image)
        try #require(bands.count == 3)
        let (reading, base, romaji) = (bands[0], bands[1], bands[2])
        #expect(abs(reading.mid - base.mid) <= 2, "reading \(reading), base \(base)")
        #expect(abs(romaji.mid - base.mid) <= 2, "romaji \(romaji), base \(base)")
        // And the view is as wide as they are, so they don't run past it.
        let view = padding...(image.width - 1 - padding)
        #expect(romaji.lowerBound >= view.lowerBound - 1, "romaji \(romaji), view \(view)")
        #expect(romaji.upperBound <= view.upperBound + 1, "romaji \(romaji), view \(view)")
    }

    /// The columns with ink in each band of rows, top to bottom: the
    /// reading, the base, and any romaji, which empty rows separate.
    private static func inkColumns(in image: CGImage) throws -> [ClosedRange<Int>] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func hasInk(_ row: Int, _ column: Int) -> Bool { pixels[(row * width + column) * 4 + 3] > 0 }
        let inkedRows = (0..<height).map { row in (0..<width).contains { hasInk(row, $0) } }

        // Bands of consecutive rows with ink, top to bottom.
        var bands: [Range<Int>] = []
        var row = 0
        while row < height {
            guard inkedRows[row] else { row += 1; continue }
            let start = row
            while row < height, inkedRows[row] { row += 1 }
            bands.append(start..<row)
        }
        return bands.compactMap { rows in
            let inked = (0..<width).filter { column in rows.contains { hasInk($0, column) } }
            guard let first = inked.first, let last = inked.last else { return nil }
            return first...last
        }
    }
}

private extension ClosedRange<Int> {
    var mid: Double { Double(lowerBound + upperBound) / 2 }
}
