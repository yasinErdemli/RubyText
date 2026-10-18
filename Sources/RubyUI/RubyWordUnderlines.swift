import RubyCore
import SwiftUI

/// Draws a line under chosen words, dotted by default, such as the words a
/// tap explains:
///
///     RubyText(segments: sentence.segments)
///         .rubyWordUnderlines(.wordIDs(wordsWithDetails))
///         .onRubyWordTap { word in showDetails(word.wordID) }
///
/// Each word gets a line of its own, short of its edges, so neighboring
/// words read as two. A line takes its word's color from
/// `rubyWordColors(_:in:)`, faded, or the secondary foreground style.
/// Underlined text keeps a little more room below each line, between the
/// text and any romaji under it.
public struct RubyWordUnderlines: Hashable, Sendable {
    private enum Rule: Hashable, Sendable {
        case words(Set<String>)
        case wordIDs(Set<String>)
    }

    private let rule: Rule
    /// How the lines are drawn.
    public let pattern: RubyUnderlinePattern

    /// Underlines chosen words. Each matches a word as written (名前), a
    /// word in any conjugation by its dictionary form (生まれる matches
    /// 生まれた), or a run of whole words (見当がつく), underlined as one.
    public static func words(_ words: some Sequence<String>, pattern: RubyUnderlinePattern = .dotted) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .words(Set(words)), pattern: pattern)
    }

    /// Underlines the words with chosen IDs, which you give their segments
    /// as `wordID`: each word exactly, wherever it is, and no other word
    /// written the same.
    public static func wordIDs(_ ids: some Sequence<String>, pattern: RubyUnderlinePattern = .dotted) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .wordIDs(Set(ids)), pattern: pattern)
    }

    /// The ranges of `content` with a line under them: one per match, so
    /// neighboring words get lines of their own, and a word in pieces, or
    /// a run of words matched together, gets one.
    func ranges(in content: RubyContent) -> [Range<Int>] {
        // Words are matched as written, then underlined wherever rewriting
        // moved them.
        let source = content.original ?? content
        let matches = matches(for: source.words, in: source.string)
        var ranges: [(range: Range<Int>, match: String)] = []
        for (word, match) in zip(content.words, matches) {
            guard let match else { continue }
            if let last = ranges.last, last.match == match, last.range.upperBound == word.range.lowerBound {
                ranges[ranges.count - 1].range = last.range.lowerBound..<word.range.upperBound
            } else {
                ranges.append((word.range, match))
            }
        }
        return ranges.map(\.range)
    }

    /// What each of `words`, from `text`, is underlined for: the key or ID
    /// it matched, the same for the words of one match, or nil.
    private func matches(for words: [RubyWord], in text: String) -> [String?] {
        switch rule {
        case .words(let chosen):
            RubyChosenWords.values(Dictionary(uniqueKeysWithValues: chosen.map { ($0, $0) }), for: words, in: text)
        case .wordIDs(let ids):
            words.map { word in word.wordID.flatMap { ids.contains($0) ? $0 : nil } }
        }
    }
}

/// How `RubyWordUnderlines` draws its lines.
public enum RubyUnderlinePattern: Hashable, Sendable {
    /// Round dots, as many apps mark words with more to show.
    case dotted
    /// Short dashes.
    case dashed
    /// A solid line.
    case solid
}

extension EnvironmentValues {
    /// Which words `RubyText` underlines. None by default.
    @Entry var rubyWordUnderlines: RubyWordUnderlines? = nil
}

extension View {
    /// Draws a line under chosen words in `RubyText` views in this
    /// hierarchy, dotted by default. Pass `nil` to underline none.
    public func rubyWordUnderlines(_ underlines: RubyWordUnderlines?) -> some View {
        environment(\.rubyWordUnderlines, underlines)
    }
}
