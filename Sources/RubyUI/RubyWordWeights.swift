import RubyCore
import SwiftUI

/// Sets the weight of chosen words, to make them bold, such as the form a
/// grammar point teaches.
///
/// Combine it with `rubyWordColors(_:in:)` to make words bold as well as
/// colored:
///
///     RubyText(segments: sentence.segments)
///         .rubyWordWeights(.wordIDs(point.formIDs))
///         .rubyWordColors(.wordIDs(point.formIDs), in: .background)
///
/// A word's furigana and romaji take its weight. Other words keep the
/// font's.
public struct RubyWordWeights: Hashable, Sendable {
    private enum Rule: Hashable, Sendable {
        case words([String: Font.Weight])
        case wordIDs([String: Font.Weight])
    }

    private let rule: Rule

    /// Sets the weight of chosen words, such as a lesson's vocabulary. Each
    /// key matches a word as written (名前), a word in any conjugation by
    /// its dictionary form (生まれる matches 生まれた), or a run of whole
    /// words (見当がつく).
    public static func words(_ weights: [String: Font.Weight]) -> RubyWordWeights {
        RubyWordWeights(rule: .words(weights))
    }

    /// Sets chosen words in one weight, bold by default.
    public static func words(_ words: some Sequence<String>, weight: Font.Weight = .bold) -> RubyWordWeights {
        RubyWordWeights(rule: .words(Dictionary(words.map { ($0, weight) }, uniquingKeysWith: { first, _ in first })))
    }

    /// Sets the weight of the words with chosen IDs, which you give their
    /// segments as `wordID`: each word exactly, wherever it is, and no
    /// other word written the same.
    ///
    ///     RubyText(segments: sentence.segments)
    ///         .rubyWordWeights(.wordIDs(["must": .bold, "eat": .semibold]))
    public static func wordIDs(_ weights: [String: Font.Weight]) -> RubyWordWeights {
        RubyWordWeights(rule: .wordIDs(weights))
    }

    /// Sets the words with chosen IDs in one weight, bold by default, such
    /// as a grammar point's form.
    public static func wordIDs(_ ids: some Sequence<String>, weight: Font.Weight = .bold) -> RubyWordWeights {
        RubyWordWeights(rule: .wordIDs(Dictionary(ids.map { ($0, weight) }, uniquingKeysWith: { first, _ in first })))
    }

    /// The weight of each of `words`, which come from `text`.
    func weights(for words: [RubyWord], in text: String) -> [Font.Weight?] {
        switch rule {
        case .words(let weights):
            RubyChosenWords.values(weights, for: words, in: text)
        case .wordIDs(let weights):
            words.map { $0.wordID.flatMap { weights[$0] } }
        }
    }
}

extension EnvironmentValues {
    /// Which words `RubyText` sets in their own weight. None by default.
    @Entry var rubyWordWeights: RubyWordWeights? = nil
}

extension View {
    /// Sets the weight of chosen words in `RubyText` views in this
    /// hierarchy, to make them bold. Pass `nil` to set none.
    public func rubyWordWeights(_ weights: RubyWordWeights?) -> some View {
        environment(\.rubyWordWeights, weights)
    }
}
