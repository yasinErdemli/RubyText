import RubyCore
import SwiftUI

/// Colors individual words, to show learners how a sentence is built.
///
/// Color by grammar, mark where words begin and end, pick out vocabulary,
/// or show JLPT levels. Each can color the text or the background behind
/// it, and a text coloring and a background coloring can be combined:
///
///     RubyText("吾輩は猫である。名前はまだ無い。")
///         .rubyWordColors(.partOfSpeech)
///         .rubyWordColors(.words(["猫", "名前"]), in: .background)
///
/// A colored word's furigana and romaji take its color.
public struct RubyWordColors: Hashable, Sendable {
    private enum Rule: Hashable, Sendable {
        case partOfSpeech([RubyPartOfSpeech: Color])
        case alternating([Color])
        case words([String: Color])
        case wordIDs([String: Color])
        case jlpt([RubyJLPTLevel: Color], vocabulary: [String: RubyJLPTLevel])
        case readingSources([RubyReadingSource: Color])
    }

    private let rule: Rule

    /// Colors each word by its grammatical role: nouns blue, verbs red,
    /// adjectives green, particles orange, and so on.
    public static let partOfSpeech = partOfSpeech(defaultPartOfSpeechColors)

    /// Colors each word by its grammatical role, with your own colors.
    /// Roles without a color stay uncolored.
    public static func partOfSpeech(_ colors: [RubyPartOfSpeech: Color]) -> RubyWordColors {
        RubyWordColors(rule: .partOfSpeech(colors))
    }

    /// The colors `partOfSpeech` uses.
    static let defaultPartOfSpeechColors: [RubyPartOfSpeech: Color] = [
        .noun: .blue,
        .verb: .red,
        .adjective: .green,
        .adverb: .purple,
        .particle: .orange,
        .auxiliary: .brown,
        .adnominal: .teal,
        .conjunction: .indigo,
        .prefix: .mint,
        .interjection: .cyan,
    ]

    /// Alternates between two colors from word to word, to show where each
    /// word begins and ends in text without spaces.
    public static let alternating = alternating([.blue, .orange])

    /// Cycles through `colors` from word to word.
    public static func alternating(_ colors: [Color]) -> RubyWordColors {
        RubyWordColors(rule: .alternating(colors))
    }

    /// Colors chosen words, such as a lesson's vocabulary. Each key matches
    /// a word as written (名前), a word in any conjugation by its dictionary
    /// form (生まれる matches 生まれた), or a run of whole words (見当がつく).
    public static func words(_ colors: [String: Color]) -> RubyWordColors {
        RubyWordColors(rule: .words(colors))
    }

    /// Colors chosen words with one color.
    public static func words(_ words: some Sequence<String>, color: Color = .orange) -> RubyWordColors {
        RubyWordColors(rule: .words(Dictionary(words.map { ($0, color) }, uniquingKeysWith: { first, _ in first })))
    }

    /// Colors the words with chosen IDs, which you give their segments as
    /// `wordID`: each word exactly, wherever it is, and no other word
    /// written the same.
    ///
    ///     RubyText(segments: sentence.segments)
    ///         .rubyWordColors(.wordIDs(["food": .orange, "eat": .blue]))
    public static func wordIDs(_ colors: [String: Color]) -> RubyWordColors {
        RubyWordColors(rule: .wordIDs(colors))
    }

    /// Colors the words with chosen IDs with one color, such as a lesson's
    /// new words.
    public static func wordIDs(_ ids: some Sequence<String>, color: Color = .orange) -> RubyWordColors {
        RubyWordColors(rule: .wordIDs(Dictionary(ids.map { ($0, color) }, uniquingKeysWith: { first, _ in first })))
    }

    /// Colors each word by its JLPT level, from green for N5 to red for N1.
    public static let jlpt = jlpt()

    /// Colors each word by its JLPT level, from green for N5 to red for N1,
    /// only above `level`, to mark the words a learner doesn't know yet:
    ///
    ///     .jlpt(above: .n4)   // N3, N2 and N1 words
    ///
    /// A word's level is its hardest kanji's level. Kanji beyond the JLPT
    /// count as N1, and words without kanji have no level unless
    /// `vocabulary` gives them one. `vocabulary` maps words, as written or
    /// in dictionary form, to levels from your own word lists, and takes
    /// precedence over kanji.
    public static func jlpt(above level: RubyJLPTLevel? = nil, vocabulary: [String: RubyJLPTLevel] = [:]) -> RubyWordColors {
        jlpt(defaultJLPTColors.filter { key, _ in level.map { key > $0 } ?? true }, vocabulary: vocabulary)
    }

    /// Colors each word by its JLPT level, with your own colors. Levels
    /// without a color stay uncolored:
    ///
    ///     .jlpt([.n2: .orange, .n1: .red])
    public static func jlpt(_ colors: [RubyJLPTLevel: Color], vocabulary: [String: RubyJLPTLevel] = [:]) -> RubyWordColors {
        RubyWordColors(rule: .jlpt(colors, vocabulary: vocabulary))
    }

    /// The colors `jlpt` uses.
    static let defaultJLPTColors: [RubyJLPTLevel: Color] = [
        .n5: .green,
        .n4: .blue,
        .n3: .purple,
        .n2: .orange,
        .n1: .red,
    ]

    /// Colors each word by where its reading came from, to check readings:
    /// yours purple, rules' orange, and Apple's model's green. The
    /// dictionary's stay uncolored.
    public static let readingSources = readingSources(defaultReadingSourceColors)

    /// Colors each word by where its reading came from, with your own
    /// colors. Sources without a color stay uncolored.
    ///
    ///     .rubyWordColors(.readingSources([.model: .green]))  // the model's changes
    public static func readingSources(_ colors: [RubyReadingSource: Color]) -> RubyWordColors {
        RubyWordColors(rule: .readingSources(colors))
    }

    /// The colors `readingSources` uses.
    static let defaultReadingSourceColors: [RubyReadingSource: Color] = [
        .manual: .purple,
        .rule: .orange,
        .model: .green,
    ]

    /// The color this coloring gives words with `role`, if it colors by
    /// grammar: to show a key to the colors.
    public func color(for role: RubyPartOfSpeech) -> Color? {
        if case .partOfSpeech(let colors) = rule { colors[role] } else { nil }
    }

    /// The color this coloring gives words at `level`, if it colors by
    /// JLPT level.
    public func color(for level: RubyJLPTLevel) -> Color? {
        if case .jlpt(let colors, _) = rule { colors[level] } else { nil }
    }

    /// The color this coloring gives readings from `source`, if it colors
    /// by where readings came from.
    public func color(for source: RubyReadingSource) -> Color? {
        if case .readingSources(let colors) = rule { colors[source] } else { nil }
    }

    /// The color of each of `words`, which come from `text`.
    func colors(for words: [RubyWord], in text: String) -> [Color?] {
        switch rule {
        case .partOfSpeech(let colors):
            return words.map { $0.partOfSpeech.flatMap { colors[$0] } }
        case .alternating(let colors):
            guard !colors.isEmpty else { return words.map { _ in nil } }
            return words.indices.map { colors[$0 % colors.count] }
        case .words(let colors):
            return RubyChosenWords.values(colors, for: words, in: text)
        case .wordIDs(let colors):
            return words.map { $0.wordID.flatMap { colors[$0] } }
        case .jlpt(let colors, let vocabulary):
            let levels = words.map { word in
                RubyJLPTLevel.level(
                    of: RubyReadingUnits.substring(of: text, utf16Range: word.range),
                    dictionaryForm: word.dictionaryForm,
                    vocabulary: vocabulary
                )
            }
            return Self.spreadingToEndings(levels.map { $0.flatMap { colors[$0] } }, words: words)
        case .readingSources(let colors):
            return words.map { colors[$0.source] }
        }
    }

    /// Gives a colored verb or adjective's uncolored conjugated endings its
    /// color, so 生まれた is colored as one word.
    private static func spreadingToEndings(_ colors: [Color?], words: [RubyWord]) -> [Color?] {
        var colors = colors
        for index in words.indices.dropFirst() where colors[index] == nil {
            guard let previous = colors[index - 1],
                  words[index].attachesToPrevious == true,
                  words[index].range.lowerBound == words[index - 1].range.upperBound,
                  let role = words[index].partOfSpeech, role == .auxiliary || role == .verb || role == .adjective,
                  let head = words[..<index].last(where: { $0.partOfSpeech != .auxiliary })?.partOfSpeech,
                  head == .verb || head == .adjective
            else { continue }
            colors[index] = previous
        }
        return colors
    }
}

/// Finds chosen words in text, for colorings and weights that pick words
/// out by how they're written.
enum RubyChosenWords {
    /// The value of each of `words`, which come from `text`: the value of
    /// the key each matches, if any. A key matches a word as written (名前),
    /// a word in any conjugation by its dictionary form (生まれる matches
    /// 生まれた), or a run of whole words (見当がつく).
    static func values<Value>(_ values: [String: Value], for words: [RubyWord], in text: String) -> [Value?] {
        let surfaces = words.map { RubyReadingUnits.substring(of: text, utf16Range: $0.range) }
        var result = [Value?](repeating: nil, count: words.count)
        var index = 0
        while index < words.count {
            guard let (value, count) = match(values, at: index, words: words, surfaces: surfaces) else {
                index += 1
                continue
            }
            var end = index + count
            // Include a verb or adjective's conjugated endings, so 生まれる
            // marks all of 生まれた, but not the particles after it.
            if let last = words[end - 1].partOfSpeech, last == .verb || last == .adjective {
                while end < words.count,
                      words[end].attachesToPrevious == true,
                      words[end].range.lowerBound == words[end - 1].range.upperBound,
                      let role = words[end].partOfSpeech, role == .auxiliary || role == .verb || role == .adjective {
                    end += 1
                }
            }
            for covered in index..<end { result[covered] = value }
            index = end
        }
        return result
    }

    /// The value and number of words matched starting at `index`. The
    /// longest match wins, so 見当がつく takes precedence over 見当.
    private static func match<Value>(
        _ values: [String: Value],
        at index: Int,
        words: [RubyWord],
        surfaces: [String]
    ) -> (Value, Int)? {
        var best: (value: Value, count: Int)?
        if let value = values[surfaces[index]] ?? words[index].dictionaryForm.flatMap({ values[$0] }) {
            best = (value, 1)
        }
        // Keys spanning several adjacent words, as written or ending in a
        // dictionary form (見当がつく matches 見当がつか).
        for (key, value) in values {
            var written = surfaces[index]
            var end = index + 1
            while end < words.count, written.count < key.count,
                  words[end].range.lowerBound == words[end - 1].range.upperBound {
                let lemma = written + (words[end].dictionaryForm ?? surfaces[end])
                written += surfaces[end]
                end += 1
                if written == key || lemma == key, end - index > best?.count ?? 0 {
                    best = (value, end - index)
                }
            }
        }
        return best
    }
}

/// Where `RubyWordColors` are applied.
public enum RubyWordColorPlacement: Hashable, Sendable {
    /// Colors the word's glyphs.
    case text
    /// Draws a rounded background behind the word and its annotations,
    /// lightened so the text stays readable.
    case background
}

/// The word colorings in effect: one for text and one for backgrounds.
struct RubyWordColoring: Hashable, Sendable {
    var text: RubyWordColors?
    var background: RubyWordColors?

    var isEmpty: Bool { text == nil && background == nil }
}

extension EnvironmentValues {
    /// How `RubyText` colors individual words. None by default.
    @Entry var rubyWordColoring = RubyWordColoring()
}

extension View {
    /// Colors individual words in `RubyText` views in this hierarchy.
    ///
    /// Text and background colorings are set independently, so call this
    /// once for each to combine them. Pass `nil` to remove a coloring.
    public func rubyWordColors(_ colors: RubyWordColors?, in placement: RubyWordColorPlacement = .text) -> some View {
        transformEnvironment(\.rubyWordColoring) { coloring in
            switch placement {
            case .text: coloring.text = colors
            case .background: coloring.background = colors
            }
        }
    }
}
