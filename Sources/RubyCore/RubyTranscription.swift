import Foundation
import RubyTransliteration

/// A writing system for Japanese text or its readings.
public enum RubyScript: Hashable, Sendable, CaseIterable {
    case hiragana
    case katakana
    /// Hepburn romaji, with long vowels written with macrons (tōkyō).
    case romaji
}

extension RubyContent {
    /// This content written entirely in `script`: kanji become their
    /// readings and kana the script's kana, or everything becomes romaji,
    /// with spaces between words and Japanese punctuation made Latin.
    /// Words keep their grammar and move with their text.
    package func transcribed(to script: RubyScript) -> RubyContent {
        rewritten(.transcribed(script))
    }

    /// This content with each kanji's reading in parentheses after it, in
    /// `script`: 感（かん）じ取（と）れた. Readings in markup keep their
    /// kana in hiragana, as furigana do.
    package func withInlineReadings(in script: RubyScript, parentheses: (open: String, close: String) = ("（", "）")) -> RubyContent {
        rewritten(.inlineReadings(script, open: parentheses.open, close: parentheses.close))
    }

    /// The reading `reading` shows in `script`, as furigana or inline:
    /// readings in markup keep their kana in hiragana ({本気|マジ}).
    package static func text(of reading: RubyReading, in script: RubyScript) -> String {
        switch script {
        case .hiragana: reading.text
        case .katakana: RubyKana.katakana(reading.text)
        case .romaji: RubyRomaji.hepburn(reading.text)
        }
    }

    // MARK: Rewriting

    private enum Rewrite: Hashable {
        case transcribed(RubyScript)
        case inlineReadings(RubyScript, open: String, close: String)
    }

    private struct RewriteKey: Hashable {
        let content: ObjectIdentifier
        let rewrite: Rewrite
    }

    // Rewritten content holds the content it came from, so while it's
    // cached, no other content can take that content's identifier.
    private static let rewrites = NSCache<RubyCacheKey<RewriteKey>, RubyContent>()

    private func rewritten(_ rewrite: Rewrite) -> RubyContent {
        let key = RubyCacheKey(RewriteKey(content: ObjectIdentifier(self), rewrite: rewrite))
        if let cached = Self.rewrites.object(forKey: key), cached.original === self { return cached }
        let pieces = switch rewrite {
        case .transcribed(.romaji): romajiPieces()
        case .transcribed(let script): kanaPieces(script)
        case .inlineReadings(let script, let open, let close): inlinePieces(script, open: open, close: close)
        }
        let (string, offsets) = RubyOffsetMap.assemble(pieces, length: string.utf16.count)
        let content = RubyContent(rewriting: self, as: string, offsets: offsets, keepsRomaji: rewrite != .transcribed(.romaji))
        Self.rewrites.setObject(content, forKey: key)
        return content
    }

    /// Each reading in `script`'s kana in place of its kanji, and every
    /// other character converted on its own.
    private func kanaPieces(_ script: RubyScript) -> [RubyRewritePiece] {
        func convert(_ text: String) -> String {
            script == .katakana ? RubyKana.katakana(text) : RubyKana.hiragana(text)
        }
        var readings = words.flatMap(\.furigana)[...]
        var pieces: [RubyRewritePiece] = []
        var offset = 0
        for character in string {
            let length = character.utf16.count
            defer { offset += length }
            // A reading takes the place of all the characters it covers.
            if let reading = readings.first, reading.range.lowerBound <= offset {
                if reading.range.lowerBound == offset {
                    pieces.append(RubyRewritePiece(range: reading.range, text: convert(reading.text)))
                }
                if offset + length >= reading.range.upperBound { readings = readings.dropFirst() }
                continue
            }
            pieces.append(RubyRewritePiece(range: offset..<(offset + length), text: convert(String(character))))
        }
        return pieces
    }

    /// Each word in romaji, as `RubyText` writes it below the text, and
    /// the text between words, such as punctuation, transliterated.
    private func romajiPieces() -> [RubyRewritePiece] {
        var pieces: [RubyRewritePiece] = []
        var offset = 0
        func addText(upTo end: Int) {
            guard offset < end else { return }
            let text = RubyReadingUnits.substring(of: string, utf16Range: offset..<end)
            pieces.append(RubyRewritePiece(range: offset..<end, text: RubyRomaji.hepburn(text)))
        }
        for group in romajiWords {
            addText(upTo: group.range.lowerBound)
            // Romaji joining several words (読ん|だ, yonda) are divided
            // between them where they're simply each word's romaji
            // together, so each word keeps its own.
            let inside = words.filter { group.range.contains($0.range.lowerBound) }
            let parts = inside.compactMap(\.romaji)
            if parts.count == inside.count, parts.joined() == group.text {
                for (index, (word, part)) in zip(inside, parts).enumerated() {
                    pieces.append(RubyRewritePiece(range: word.range, text: part, joinsPrevious: index > 0))
                }
            } else {
                pieces.append(RubyRewritePiece(range: group.range, text: group.text))
            }
            offset = group.range.upperBound
        }
        addText(upTo: string.utf16.count)

        // Words are spaced apart, except before punctuation that follows
        // a word directly and after punctuation that opens.
        var last: Character?
        for index in pieces.indices {
            guard let first = pieces[index].text.first else { continue }
            if !pieces[index].joinsPrevious, let last, !last.isWhitespace, !first.isWhitespace,
               !Self.opening.contains(last), !Self.closing.contains(first) {
                pieces[index].separator = " "
            }
            last = pieces[index].text.last
        }
        return pieces
    }

    /// Punctuation the next word follows without a space.
    private static let opening: Set<Character> = ["“", "‘", "(", "["]
    /// Punctuation that follows the word before it without a space.
    private static let closing: Set<Character> = [",", ".", "!", "?", ":", ";", "”", "’", ")", "]", "…"]

    /// Each reading in parentheses after its kanji; the rest unchanged.
    private func inlinePieces(_ script: RubyScript, open: String, close: String) -> [RubyRewritePiece] {
        var pieces: [RubyRewritePiece] = []
        var offset = 0
        for reading in words.flatMap(\.furigana) where reading.range.lowerBound >= offset {
            if offset < reading.range.lowerBound {
                let text = RubyReadingUnits.substring(of: string, utf16Range: offset..<reading.range.lowerBound)
                pieces.append(RubyRewritePiece(range: offset..<reading.range.lowerBound, text: text))
            }
            let base = RubyReadingUnits.substring(of: string, utf16Range: reading.range)
            pieces.append(RubyRewritePiece(
                range: reading.range,
                text: base + open + Self.text(of: reading, in: script) + close,
                keepsOffsets: true
            ))
            offset = reading.range.upperBound
        }
        if offset < string.utf16.count {
            let text = RubyReadingUnits.substring(of: string, utf16Range: offset..<string.utf16.count)
            pieces.append(RubyRewritePiece(range: offset..<string.utf16.count, text: text))
        }
        return pieces
    }
}

/// A stretch of text and what it's rewritten as.
struct RubyRewritePiece {
    /// UTF-16 range in the original text.
    let range: Range<Int>
    let text: String
    /// Whether the piece continues the romaji word before it, so no space
    /// goes between them.
    var joinsPrevious = false
    /// Whether offsets within the piece keep their place, because it
    /// starts with the original text: 東京 in 東京（とうきょう）.
    var keepsOffsets = false
    /// Put before the piece, belonging to neither it nor the piece before:
    /// the space between romaji words.
    var separator = ""
}

/// Where each UTF-16 offset of a text moved to when it was rewritten.
struct RubyOffsetMap {
    /// Where each offset is as the start of a range, and as its end. They
    /// differ only around a separator.
    let starts: [Int]
    let ends: [Int]

    /// Where `range` is in the rewritten text. A range starting or ending
    /// inside a piece that changed length takes the whole piece.
    func range(_ range: Range<Int>) -> Range<Int> {
        let lower = starts[clamped(range.lowerBound)]
        return lower..<max(lower, ends[clamped(range.upperBound)])
    }

    /// Where `offset` is as the end of what comes before it.
    func end(_ offset: Int) -> Int {
        ends[clamped(offset)]
    }

    private func clamped(_ offset: Int) -> Int {
        min(max(offset, 0), starts.count - 1)
    }

    /// The text `pieces` make, which cover the original text in order, and
    /// where each of the original's `length` offsets moved to.
    static func assemble(_ pieces: [RubyRewritePiece], length: Int) -> (String, RubyOffsetMap) {
        var result = ""
        var count = 0
        var starts = [Int](repeating: 0, count: length + 1)
        var ends = starts
        for piece in pieces {
            result += piece.separator
            count += piece.separator.utf16.count
            let start = count
            let size = piece.text.utf16.count
            let keepsOffsets = piece.keepsOffsets || size == piece.range.count
            for offset in piece.range {
                let moved = keepsOffsets ? start + offset - piece.range.lowerBound : nil
                starts[offset] = moved ?? start
                if offset > piece.range.lowerBound { ends[offset] = moved ?? start + size }
            }
            result += piece.text
            count += size
            ends[piece.range.upperBound] = count
        }
        starts[length] = count
        return (result, RubyOffsetMap(starts: starts, ends: ends))
    }
}
