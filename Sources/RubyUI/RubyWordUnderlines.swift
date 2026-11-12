import RubyCore
import SwiftUI

/// Draws a line under chosen words, dotted by default, such as the words a
/// tap explains:
///
///     RubyText(segments: sentence.segments)
///         .rubyWordUnderlines(.wordIDs(wordsWithDetails))
///         .onRubyWordTap { word in showDetails(word.wordID) }
///
/// Words can have lines of their own kinds, such as dots under the words a
/// tap explains and a solid line under a gap to fill:
///
///     .rubyWordUnderlines(.wordIDs(["neko": .dotted, "gap": .solid]))
///
/// A line can have a color of its own, such as the accent color under the
/// words a lesson has just taught, with the rest in grey:
///
///     .rubyWordUnderlines(.wordIDs([
///         "neko": RubyUnderlineStyle(color: .accentColor),
///         "inu": RubyUnderlineStyle(),
///     ]))
///
/// Each word gets a line of its own, short of its edges, so neighboring
/// words read as two. A line without a color of its own takes its word's
/// color from `rubyWordColors(_:in:)`, faded, or the secondary foreground
/// style.
/// Underlined text keeps a little more room below each line, between the
/// text and any romaji under it.
public struct RubyWordUnderlines: Hashable, Sendable {
    private enum Rule: Hashable, Sendable {
        case words([String: RubyUnderlineStyle])
        case wordIDs([String: RubyUnderlineStyle])
    }

    private let rule: Rule
    /// How the lines are drawn, when they're all drawn alike: dotted when
    /// words have kinds of their own.
    @available(*, deprecated, message: "Words can have lines of their own kinds, so there's no one pattern.")
    public var pattern: RubyUnderlinePattern {
        let all = Set(styles.values.map(\.pattern))
        return all.count == 1 ? all.first! : .dotted
    }

    /// Underlines chosen words. Each matches a word as written (名前), a
    /// word in any conjugation by its dictionary form (生まれる matches
    /// 生まれた), or a run of whole words (見当がつく), underlined as one.
    public static func words(_ words: some Sequence<String>, pattern: RubyUnderlinePattern = .dotted) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .words(Self.styles(words, pattern)))
    }

    /// Underlines chosen words, each with its own kind of line, matched
    /// as `words(_:pattern:)` matches them.
    public static func words(_ patterns: [String: RubyUnderlinePattern]) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .words(patterns.mapValues { RubyUnderlineStyle(pattern: $0) }))
    }

    /// Underlines chosen words, each with its own kind of line and,
    /// where it's given, its own color, matched as `words(_:pattern:)`
    /// matches them.
    public static func words(_ styles: [String: RubyUnderlineStyle]) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .words(styles))
    }

    /// Underlines the words with chosen IDs, which you give their segments
    /// as `wordID`: each word exactly, wherever it is, and no other word
    /// written the same.
    public static func wordIDs(_ ids: some Sequence<String>, pattern: RubyUnderlinePattern = .dotted) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .wordIDs(Self.styles(ids, pattern)))
    }

    /// Underlines the words with chosen IDs, each with its own kind of
    /// line, matched as `wordIDs(_:pattern:)` matches them.
    public static func wordIDs(_ patterns: [String: RubyUnderlinePattern]) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .wordIDs(patterns.mapValues { RubyUnderlineStyle(pattern: $0) }))
    }

    /// Underlines the words with chosen IDs, each with its own kind of
    /// line and, where it's given, its own color, matched as
    /// `wordIDs(_:pattern:)` matches them.
    public static func wordIDs(_ styles: [String: RubyUnderlineStyle]) -> RubyWordUnderlines {
        RubyWordUnderlines(rule: .wordIDs(styles))
    }

    /// Every one of `keys` with the same pattern, in no color of its own.
    private static func styles(_ keys: some Sequence<String>, _ pattern: RubyUnderlinePattern) -> [String: RubyUnderlineStyle] {
        Dictionary(keys.map { ($0, RubyUnderlineStyle(pattern: pattern)) }, uniquingKeysWith: { first, _ in first })
    }

    /// The ranges of `content` with a line under them: one per match, so
    /// neighboring words get lines of their own, and a word in pieces, or
    /// a run of words matched together, gets one.
    func ranges(in content: RubyContent) -> [Range<Int>] {
        underlines(in: content).map(\.range)
    }

    /// The lines under `content`, one per match as `ranges(in:)` finds
    /// them, each with its kind of line and its own color, if it has one.
    func underlines(in content: RubyContent) -> [RubyUnderline] {
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
        return ranges.map { match in
            let style = styles[match.match] ?? RubyUnderlineStyle()
            return RubyUnderline(range: match.range, pattern: style.pattern, color: style.color)
        }
    }

    /// Each chosen word or ID's kind of line, and its color.
    private var styles: [String: RubyUnderlineStyle] {
        switch rule {
        case .words(let styles), .wordIDs(let styles): styles
        }
    }

    /// What each of `words`, from `text`, is underlined for: the key or ID
    /// it matched, the same for the words of one match, or nil.
    private func matches(for words: [RubyWord], in text: String) -> [String?] {
        switch rule {
        case .words(let chosen):
            RubyChosenWords.values(Dictionary(uniqueKeysWithValues: chosen.keys.map { ($0, $0) }), for: words, in: text)
        case .wordIDs(let ids):
            words.map { word in word.wordID.flatMap { ids[$0] == nil ? nil : $0 } }
        }
    }
}

/// A line under a word, in UTF-16 offsets of the text, its kind, and
/// its own color, if it has one.
nonisolated struct RubyUnderline: Hashable, Sendable {
    let range: Range<Int>
    let pattern: RubyUnderlinePattern
    var color: Color? = nil
}

/// How `RubyWordUnderlines` draws one word's line: its kind, and its own
/// color, if it has one.
nonisolated public struct RubyUnderlineStyle: Hashable, Sendable {
    /// How the line is drawn.
    public var pattern: RubyUnderlinePattern
    /// The line's own color, drawn as it's given, not faded; nil takes the
    /// word's color, faded, or the secondary foreground style.
    public var color: Color?

    /// A line of a kind, dotted by default, in a color of its own or, by
    /// default, its word's.
    public init(pattern: RubyUnderlinePattern = .dotted, color: Color? = nil) {
        self.pattern = pattern
        self.color = color
    }
}

/// How `RubyWordUnderlines` draws its lines.
nonisolated public enum RubyUnderlinePattern: Hashable, Sendable {
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
    /// hierarchy, dotted by default, or of each word's own kind and color.
    /// Pass `nil` to underline none.
    public func rubyWordUnderlines(_ underlines: RubyWordUnderlines?) -> some View {
        environment(\.rubyWordUnderlines, underlines)
    }
}
