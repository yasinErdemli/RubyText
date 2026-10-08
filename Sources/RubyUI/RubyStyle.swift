import RubyCore
import SwiftUI

/// Which annotations `RubyText` draws around Japanese text.
///
/// Combine options as a set; the empty set shows plain text:
///
///     RubyText("日本語を勉強しています。")
///         .rubyStyle([.furigana, .romaji])
public struct RubyStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Hiragana readings above words that contain kanji.
    public static let furigana = RubyStyle(rawValue: 1 << 0)
    /// Romaji below every Japanese word.
    public static let romaji = RubyStyle(rawValue: 1 << 1)
}

/// Which kanji get furigana, so learners only see readings they need.
///
///     RubyText("今日、政府は新しい経済政策を発表した。")
///         .rubyStyle()
///         .rubyFurigana(.above(.n4))   // readings for 政府, 経済, 政策, 発表
///
/// A reading spanning several kanji, like せいさく over 政策, shows if any
/// of them is unknown. Changing the filter fades readings in and out.
public struct RubyFuriganaFilter: Hashable, Sendable {
    /// The hardest JLPT level the learner knows, if any.
    private var knownLevel: RubyJLPTLevel?
    /// Kanji the learner knows regardless of level.
    private var knownKanji: Set<Character> = []

    /// Furigana on every kanji.
    public static let all = RubyFuriganaFilter()

    /// Furigana only on kanji harder than `level`, plus kanji beyond the
    /// JLPT. `knownKanji` hides readings for kanji the learner has learned
    /// outside the level order.
    public static func above(_ level: RubyJLPTLevel, except knownKanji: Set<Character> = []) -> RubyFuriganaFilter {
        RubyFuriganaFilter(knownLevel: level, knownKanji: knownKanji)
    }

    /// Furigana on every kanji except `knownKanji`, such as the kanji a
    /// learner has studied.
    public static func except(_ knownKanji: some Sequence<Character>) -> RubyFuriganaFilter {
        RubyFuriganaFilter(knownKanji: Set(knownKanji))
    }

    /// Whether to show the reading of `base`, the text it sits over.
    /// Readings over kana, which only manual markup creates, always show.
    func showsReading(over base: String) -> Bool {
        let kanji = base.filter(RubyJLPTKanji.isGraded)
        guard !kanji.isEmpty else { return true }
        return kanji.contains { !isKnown($0) }
    }

    private func isKnown(_ kanji: Character) -> Bool {
        if knownKanji.contains(kanji) { return true }
        guard let knownLevel, let level = RubyJLPTKanji.level(of: kanji) else { return false }
        return level <= knownLevel
    }
}

/// Visual space between words, as beginner texts write Japanese (分かち書き).
///
///     RubyText("吾輩は猫である。")
///         .rubySpacing(.phrases)   // 吾輩は 猫である。
///
/// The space is drawn, not inserted: selection and copy see the original
/// text, and no space is added before punctuation.
public struct RubySpacing: Hashable, Sendable {
    /// Where spaces go.
    public enum Boundary: Hashable, Sendable {
        /// Between words, with conjugated endings kept on their word and
        /// particles separate: 吾輩 は 猫である。
        case words
        /// Between reading phrases (文節), as in children's books:
        /// 吾輩は 猫である。
        case phrases
    }

    /// Where spaces go, or `nil` for none.
    public let boundary: Boundary?
    /// Width of each space, as a fraction of the font size.
    public let width: CGFloat

    /// No added space.
    public static let none = RubySpacing(boundary: nil, width: 0)
    /// Half-width spaces between words.
    public static let words = words(width: 0.5)
    /// Half-width spaces between reading phrases.
    public static let phrases = phrases(width: 0.5)

    /// Spaces between words, `width` times the font size wide.
    public static func words(width: CGFloat) -> RubySpacing {
        RubySpacing(boundary: .words, width: width)
    }

    /// Spaces between reading phrases, `width` times the font size wide.
    public static func phrases(width: CGFloat) -> RubySpacing {
        RubySpacing(boundary: .phrases, width: width)
    }

    /// The UTF-16 offsets where a space follows, each the end of a word or
    /// phrase directly followed by another.
    func boundaries(in content: RubyContent) -> [Int] {
        let ranges: [Range<Int>]
        switch boundary {
        case nil:
            return []
        case .phrases:
            ranges = RubyReadingUnits.units(in: content.string, words: content.words).map(\.range)
        case .words:
            // Endings and suffixes join their word; particles stand alone.
            var words: [Range<Int>] = []
            for word in content.words {
                if let last = words.last, last.upperBound == word.range.lowerBound,
                   word.attachesToPrevious == true, word.partOfSpeech != .particle {
                    words[words.count - 1] = last.lowerBound..<word.range.upperBound
                } else {
                    words.append(word.range)
                }
            }
            ranges = words
        }
        return zip(ranges, ranges.dropFirst()).compactMap { current, next in
            current.upperBound == next.lowerBound ? current.upperBound : nil
        }
    }
}

/// Where `RubyText` may break lines.
public enum RubyLineBreaking: Hashable, Sendable {
    /// Between phrases, so words stay with their particles and endings
    /// (東京へ, 日本語を) and never split across lines, like
    /// `word-break: auto-phrase` on the web. A phrase longer than a line
    /// still breaks within it.
    case words
    /// Between almost any two characters, following the rules against
    /// starting a line with 。 or ゃ.
    case anywhere

    /// The language the text is set in, which also selects its line
    /// breaking: Japanese breaks between characters, following the rules
    /// against starting a line with 。 or ゃ, and the line-word option
    /// (`lw=phrase`) breaks between phrases instead.
    var languageIdentifier: String {
        switch self {
        case .words: "ja-u-lw-phrase"
        case .anywhere: "ja"
        }
    }
}

extension EnvironmentValues {
    /// The annotations `RubyText` views draw. Plain text by default.
    @Entry var rubyStyle: RubyStyle = []
    /// Which kanji `RubyText` views show furigana for. All by default.
    @Entry var rubyFuriganaFilter = RubyFuriganaFilter.all
    /// Space `RubyText` views draw between words. None by default.
    @Entry var rubySpacing = RubySpacing.none
    /// Where `RubyText` views may break lines. Between words by default.
    @Entry var rubyLineBreaking = RubyLineBreaking.words
    /// Whether `RubyText` hides readings over numbers written in digits.
    @Entry var rubyDigitReadingsHidden = false
}

extension View {
    /// Sets which annotations `RubyText` views in this hierarchy draw.
    ///
    /// Calling it without arguments enables furigana; pass `[]` for plain text.
    public func rubyStyle(_ style: RubyStyle = .furigana) -> some View {
        environment(\.rubyStyle, style)
    }

    /// Sets which kanji `RubyText` views in this hierarchy show furigana
    /// for, such as `.above(.n4)` to hide readings of N5 and N4 kanji.
    public func rubyFurigana(_ filter: RubyFuriganaFilter) -> some View {
        environment(\.rubyFuriganaFilter, filter)
    }

    /// Adds visual space between words or reading phrases in `RubyText`
    /// views in this hierarchy, for beginners.
    public func rubySpacing(_ spacing: RubySpacing) -> some View {
        environment(\.rubySpacing, spacing)
    }

    /// Sets where `RubyText` views in this hierarchy may break lines.
    public func rubyLineBreaking(_ lineBreaking: RubyLineBreaking) -> some View {
        environment(\.rubyLineBreaking, lineBreaking)
    }

    /// Hides furigana and romaji over numbers written in digits, such as
    /// 2026年, 3日, or 10分, in `RubyText` views in this hierarchy. Numbers
    /// in kanji (三日) keep their readings, and read-aloud timing is
    /// unchanged.
    ///
    ///     RubyText("2026年3月3日に出発する。")
    ///         .rubyStyle([.furigana, .romaji])
    ///         .rubyDigitReadingsHidden()
    public func rubyDigitReadingsHidden(_ hidden: Bool = true) -> some View {
        environment(\.rubyDigitReadingsHidden, hidden)
    }
}
