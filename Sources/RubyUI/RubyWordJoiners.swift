import Foundation
import RubyCore
import SwiftUI

/// Word joiners (U+2060) put into the text `RubyText` lays out, between
/// characters a line may not break between: inside each phrase the app
/// gave in its segments, as BudouX keeps its phrases whole on the web.
///
/// The system's own phrase breaking (`lw=phrase`) doesn't know the app's
/// words, and splits some of them: ありがとうござ / いました, 森 / さん.
/// A joiner stops a break in any language and any line-breaking mode, and
/// draws nothing, so with them lines break only between the app's phrases.
///
/// The joiners are only in the laid-out text. Everything else in `RubyText`
/// counts UTF-16 offsets in the content, and `RubyLayout` converts between
/// the two with `joinedOffset(_:)` and `originalOffset(_:)`.
struct RubyWordJoiners: Hashable, Sendable {
    /// The UTF-16 offsets in the content where a joiner goes, sorted, each
    /// between two characters.
    let offsets: [Int]

    /// No joiners: the laid-out text is the content.
    static let none = RubyWordJoiners(offsets: [])

    /// The word joiner, U+2060, which forbids a line break on either side
    /// of it and has no width.
    static let character: Character = "\u{2060}"

    init(offsets: [Int]) {
        self.offsets = offsets
    }

    /// Joiners between the characters of each of `ranges` of `string`,
    /// except at the UTF-16 offsets in `breaks`.
    init(inside ranges: [Range<Int>], of string: String, except breaks: Set<Int> = []) {
        let utf16 = string.utf16
        var offsets: [Int] = []
        for range in ranges where range.count > 1 {
            let lower = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
            let upper = utf16.index(lower, offsetBy: range.count)
            // Between characters, never inside one, such as a kanji with
            // a variation selector.
            var offset = range.lowerBound
            for character in string[lower..<upper].dropLast() {
                offset += character.utf16.count
                if !breaks.contains(offset) { offsets.append(offset) }
            }
        }
        self.offsets = offsets.sorted()
    }

    var isEmpty: Bool { offsets.isEmpty }

    /// How many joiners go at offsets for which `isBefore` is true, which
    /// must hold for a first stretch of `offsets` and not after it.
    private func count(while isBefore: (Int, Int) -> Bool) -> Int {
        var low = 0
        var high = offsets.count
        while low < high {
            let mid = (low + high) / 2
            if isBefore(mid, offsets[mid]) { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Where the character at the content's UTF-16 `offset` is in the
    /// laid-out text, after the joiner before it, if there is one.
    func joinedOffset(_ offset: Int) -> Int {
        offset + count { $1 <= offset }
    }

    /// Where a range of the content is in the laid-out text: from its first
    /// character to the end of its last, with the joiners between them.
    func joinedRange(_ range: Range<Int>) -> Range<Int> {
        let lower = joinedOffset(range.lowerBound)
        let upper = range.upperBound + count { $1 < range.upperBound }
        return lower..<max(lower, upper)
    }

    /// The content's UTF-16 offset for an offset in the laid-out text; a
    /// joiner counts as the character after it.
    func originalOffset(_ joined: Int) -> Int {
        // The joiner at index i sits at offsets[i] + i in the laid-out text.
        joined - count { $1 + $0 < joined }
    }

    /// `text`, the content as attributed text, with the joiners put in.
    /// Each takes the attributes of the character before it, such as its
    /// language, but no tracking, so it adds no space.
    func inserted(into text: AttributedString) -> AttributedString {
        guard !offsets.isEmpty else { return text }
        var result = AttributedString()
        var index = text.utf16.startIndex
        var offset = 0
        for joiner in offsets {
            let next = text.utf16.index(index, offsetBy: joiner - offset)
            result.append(text[index..<next])
            let previous = text.characters.index(before: next)
            let attributes = text[previous..<next].runs.first?.attributes ?? AttributeContainer()
            var piece = AttributedString(String(Self.character), attributes: attributes)
            piece.tracking = nil
            result.append(piece)
            index = next
            offset = joiner
        }
        result.append(text[index..<text.endIndex])
        return result
    }

    /// Where each line starts in the content, from where it starts in the
    /// laid-out text: its paragraph, and its UTF-16 offset in that
    /// paragraph.
    ///
    /// - Parameter paragraphStarts: Where each paragraph starts in the
    ///   content.
    func originalLineStarts(
        _ lineStarts: [(paragraph: Int, offset: Int)],
        paragraphStarts: [Int]
    ) -> [(paragraph: Int, offset: Int)] {
        guard !offsets.isEmpty else { return lineStarts }
        return lineStarts.map { paragraph, offset in
            guard paragraphStarts.indices.contains(paragraph) else { return (paragraph, offset) }
            let start = paragraphStarts[paragraph]
            return (paragraph, originalOffset(joinedOffset(start) + offset) - start)
        }
    }

    /// `speech`, whose ranges are in the content, moved into the laid-out
    /// text.
    func moved(_ speech: [RubySpokenText]) -> [RubySpokenText] {
        guard !offsets.isEmpty else { return speech }
        return speech.map {
            $0.isPause ? RubySpokenText(pauseAt: joinedRange($0.range)) : RubySpokenText(range: joinedRange($0.range), text: $0.text)
        }
    }
}

extension RubyLineBreaking {
    /// Whether lines break only between the phrases `content` was given:
    /// breaking between phrases, in text from segments, whose phrases are
    /// the app's (`RubySegment.Word.attachesToPrevious`).
    func breaksAtGivenPhrases(in content: RubyContent) -> Bool {
        self == .phrases && content.phrasesAreGiven
    }

    /// The joiners that keep `content`'s given phrases whole: inside each
    /// phrase, but only inside each word of the phrases in `widePhrases`,
    /// which are wider than a line. A word in `wideWords` is wider than a
    /// line too, and may break between its morphemes, where that leaves
    /// two letters or more on each side (ありがとう / ござい / ました).
    /// Paragraphs in `characterBreaking` get none.
    func joiners(
        in content: RubyContent,
        widePhrases: Set<Range<Int>> = [],
        wideWords: Set<Range<Int>> = [],
        characterBreaking: Set<Int> = []
    ) -> RubyWordJoiners {
        guard breaksAtGivenPhrases(in: content) else { return .none }
        let paragraphStarts = Self.paragraphRanges(in: content.string).map(\.lowerBound)
        let words = content.words.map(\.range)
        var ranges: [Range<Int>] = []
        var breaks: Set<Int> = []
        for phrase in content.readingUnits.map(\.range) {
            let paragraph = paragraphStarts.lastIndex { $0 <= phrase.lowerBound } ?? 0
            if characterBreaking.contains(paragraph) { continue }
            if widePhrases.contains(phrase) {
                ranges += words.filter { phrase.contains($0.lowerBound) }
            } else {
                ranges.append(phrase)
            }
        }
        for word in wideWords {
            breaks.formUnion(Self.morphemeBreaks(in: word, of: content.string))
        }
        return RubyWordJoiners(inside: ranges, of: content.string, except: breaks)
    }

    /// The UTF-16 offsets inside `range` of `string` where a word too wide
    /// for a line may break: between its morphemes, as the system's word
    /// tokenizer finds them in Japanese, with two letters or more on each
    /// side, so no line holds た！ alone.
    static func morphemeBreaks(in range: Range<Int>, of string: String) -> Set<Int> {
        let utf16 = Array(string.utf16)
        guard range.lowerBound >= 0, range.upperBound <= utf16.count else { return [] }
        let word = String(utf16CodeUnits: Array(utf16[range]), count: range.count) as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, word, CFRange(location: 0, length: word.length), kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var breaks: Set<Int> = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            breaks.insert(token.location)
        }
        let characters = Array(String(word))
        var starts = [0]
        for character in characters { starts.append(starts[starts.count - 1] + character.utf16.count) }
        return Set(breaks.filter { offset in
            guard let index = starts.firstIndex(of: offset) else { return false }
            let before = characters[..<index].count(where: \.isLetter)
            let after = characters[index...].count(where: \.isLetter)
            return before >= 2 && after >= 2
        }.map { range.lowerBound + $0 })
    }

    /// Adds the given phrases and words that lines start inside to
    /// `widePhrases` and `wideWords`: a phrase or word wider than its line
    /// breaks wherever the line runs out. A phrase found wide breaks
    /// between its words next time, and a word found wide in a phrase
    /// already breaking so, between the system's phrases in it.
    ///
    /// - Parameters:
    ///   - string: The content's text.
    ///   - lineStarts: Where each line starts in the content: its
    ///     paragraph, and its UTF-16 offset in that paragraph.
    ///   - paragraphStarts: Where each paragraph starts in the content.
    ///   - characterBreaking: Paragraphs already breaking between
    ///     characters, which are left as they are.
    /// - Returns: Whether any phrase or word was added.
    static func findWide(
        in string: String,
        lineStarts: [(paragraph: Int, offset: Int)],
        paragraphStarts: [Int],
        phrases: [Range<Int>],
        words: [Range<Int>],
        characterBreaking: Set<Int>,
        widePhrases: inout Set<Range<Int>>,
        wideWords: inout Set<Range<Int>>
    ) -> Bool {
        var found = false
        let characters = Array(string)
        var starts = [0]
        for character in characters { starts.append(starts[starts.count - 1] + character.utf16.count) }
        for (paragraph, offset) in lineStarts where paragraphStarts.indices.contains(paragraph) && !characterBreaking.contains(paragraph) {
            let start = paragraphStarts[paragraph] + offset
            // A phrase that only just fits leaves the 。 or ！ after it to
            // start the next line.
            let startsBadly = starts.firstIndex(of: start).map { characters.indices.contains($0) && !canStartLine(characters[$0]) } ?? false
            let phrase = range(around: start, in: phrases) ?? (startsBadly ? phrases.first { $0.upperBound == start } : nil)
            guard let phrase else { continue }
            let word = range(around: start, in: words) ?? (startsBadly ? words.first { $0.upperBound == start } : nil)
            if widePhrases.insert(phrase).inserted {
                found = true
            } else if let word, wideWords.insert(word).inserted {
                found = true
            }
        }
        return found
    }

    /// The first of `ranges` that `offset` falls inside, after its start.
    static func range(around offset: Int, in ranges: [Range<Int>]) -> Range<Int>? {
        ranges.first { $0.lowerBound < offset && offset < $0.upperBound }
    }
}
