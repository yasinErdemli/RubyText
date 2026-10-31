import RubyCore
import SwiftUI

/// Shows chosen words as blanks to fill, such as the gap in an exercise:
///
///     RubyText(segments: sentence.segments)
///         .rubyBlanks(.wordIDs(["gap"]))
///
/// Give the blank the words that fill it. It keeps their place, and the
/// room their readings and romaji take, so nothing moves when they show
/// again. It's drawn as an empty rounded box the height of the line,
/// tinted with the tint color and outlined in it, with nothing in it or
/// over or under it. A reader never marks it, a tap on it does nothing,
/// and it isn't one of the words VoiceOver users can choose.
///
/// VoiceOver pauses at a blank rather than reading it. To have it say
/// "blank" in your app's language, give the text a label of its own.
/// Selection and copy still see the words, so where the text can be
/// selected, a blank doesn't keep them secret.
public struct RubyBlanks: Hashable, Sendable {
    private let ids: Set<String>

    /// Blanks out the words with chosen IDs, which you give their segments
    /// as `wordID`. Neighboring words with chosen IDs make one blank.
    public static func wordIDs(_ ids: some Sequence<String>) -> RubyBlanks {
        RubyBlanks(ids: Set(ids))
    }

    /// The ranges of `content` that are blanks, in UTF-16 offsets of the
    /// text, one per run of neighboring chosen words.
    func ranges(in content: RubyContent) -> [Range<Int>] {
        // Words are chosen as written, then blanked wherever rewriting
        // moved them.
        let source = content.original ?? content
        var ranges: [Range<Int>] = []
        for (word, chosen) in zip(content.words, source.words.map { $0.wordID.map(ids.contains) ?? false }) where chosen {
            if let last = ranges.last, last.upperBound == word.range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<word.range.upperBound
            } else {
                ranges.append(word.range)
            }
        }
        return ranges
    }
}

extension EnvironmentValues {
    /// Which words `RubyText` shows as blanks. None by default.
    @Entry var rubyBlanks: RubyBlanks? = nil
}

extension View {
    /// Shows chosen words in `RubyText` views in this hierarchy as blanks
    /// to fill, keeping their place. Pass `nil` for none.
    public func rubyBlanks(_ blanks: RubyBlanks?) -> some View {
        environment(\.rubyBlanks, blanks)
    }
}

extension RubyText {
    /// What VoiceOver says for parts of the text, with a pause at each of
    /// `blanks` in place of anything said for the words in it.
    static func speech(_ speech: [RubySpokenText], pausingAt blanks: [Range<Int>]) -> [RubySpokenText] {
        guard !blanks.isEmpty else { return speech }
        let outside = speech.filter { item in !blanks.contains { $0.overlaps(item.range) } }
        return (outside + blanks.map(RubySpokenText.init(pauseAt:))).sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
