import Foundation
import RubyTransliteration

/// Writes Japanese text out in kana or romaji, or with each kanji's
/// reading in parentheses after it, as plain strings: for search, sharing,
/// or anywhere that can't draw ruby.
///
///     let converter = RubyConverter(analyzer: analyzer)
///     converter.convert("感じ取れたら手を繋ごう", to: .hiragana)
///     // かんじとれたらてをつなごう
///     converter.convert("感じ取れたら手を繋ごう", to: .romaji)
///     // kanjitoretara te o tsunagō
///     converter.annotate("感じ取れたら手を繋ごう", with: .hiragana)
///     // 感（かん）じ取（と）れたら手（て）を繋（つな）ごう
///
/// Readings are the ones `RubyText` shows with the same analyzer, and
/// `{base|reading}` markup supplies your own where it's wrong.
public struct RubyConverter: Sendable {
    /// The writing system readings are written in.
    public enum Script: Hashable, Sendable, CaseIterable {
        case hiragana
        case katakana
        /// Hepburn romaji, as `RubyText` writes them: with spaces between
        /// words, and long vowels with macrons.
        case romaji
    }

    private let analyzer: (any RubyAnalyzer)?

    /// A converter reading text with `analyzer`, such as a
    /// `RubyMeCabAnalyzer` with the IPAdic dictionary your app bundles.
    public init(analyzer: some RubyAnalyzer) {
        self.analyzer = analyzer
    }

    /// A converter that only knows the readings in `{base|reading}` markup.
    public init() {
        analyzer = nil
    }

    /// `markup` written entirely in `script`: kanji become their readings,
    /// and kana the script's kana. Romaji put spaces between words and
    /// turn Japanese punctuation into Latin.
    ///
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .hiragana)  // きょうはこーひーをのんだ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .katakana)  // キョウハコーヒーヲノンダ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .romaji)    // kyō wa kōhī o nonda.
    ///
    /// Words without a known reading, such as kanji without an analyzer,
    /// stay as they're written.
    public func convert(_ markup: String, to script: Script) -> String {
        let content = content(for: markup)
        switch script {
        case .hiragana: return RubyKana.hiragana(Self.spelledOut(content))
        case .katakana: return RubyKana.katakana(Self.spelledOut(content))
        case .romaji: return Self.romaji(content)
        }
    }

    /// `markup` with the reading of each kanji in parentheses after it,
    /// in `script`; everything else as it's written.
    ///
    ///     converter.annotate("東京へ行きたい。", with: .hiragana)  // 東京（とうきょう）へ行（い）きたい。
    ///     converter.annotate("東京へ行きたい。", with: .romaji)    // 東京（tōkyō）へ行（i）きたい。
    ///
    /// Readings you supply in markup keep the kana you wrote them in,
    /// unless `script` is katakana or romaji: `{本気|マジ}` is 本気（マジ）.
    ///
    /// - Parameter parentheses: What the readings are put between. Full
    ///   width, as Japanese text writes them, by default.
    public func annotate(_ markup: String, with script: Script, parentheses: (open: String, close: String) = ("（", "）")) -> String {
        let content = content(for: markup)
        let readings = content.words.flatMap(\.furigana).map { reading in
            let base = RubyReadingUnits.substring(of: content.string, utf16Range: reading.range)
            let text = switch script {
            case .hiragana: reading.text
            case .katakana: RubyKana.katakana(reading.text)
            case .romaji: RubyRomaji.hepburn(reading.text)
            }
            return (range: reading.range, text: base + parentheses.open + text + parentheses.close)
        }
        return Self.replacing(readings, in: content.string)
    }

    private func content(for markup: String) -> RubyContent {
        RubyContent.content(for: markup, analyzer: analyzer)
    }

    /// The text with the kanji spelled out in their readings: 今日は晴れ is
    /// きょうははれ.
    private static func spelledOut(_ content: RubyContent) -> String {
        replacing(content.words.flatMap(\.furigana).map { ($0.range, $0.text) }, in: content.string)
    }

    /// The text in romaji: each word as `RubyText` writes it below the
    /// text, and the text between words, such as punctuation, transliterated.
    private static func romaji(_ content: RubyContent) -> String {
        var pieces: [String] = []
        var position = 0
        func addText(upTo end: Int) {
            guard position < end else { return }
            pieces.append(RubyRomaji.hepburn(RubyReadingUnits.substring(of: content.string, utf16Range: position..<end)))
        }
        for word in content.romajiWords {
            addText(upTo: word.range.lowerBound)
            pieces.append(word.text)
            position = word.range.upperBound
        }
        addText(upTo: content.string.utf16.count)

        var result = ""
        for piece in pieces {
            guard let first = piece.first else { continue }
            if let last = result.last, !last.isWhitespace, !first.isWhitespace,
               !opening.contains(last), !closing.contains(first) {
                result += " "
            }
            result += piece
        }
        return result
    }

    /// Punctuation the next word follows without a space.
    private static let opening: Set<Character> = ["“", "‘", "(", "["]
    /// Punctuation that follows the word before it without a space.
    private static let closing: Set<Character> = [",", ".", "!", "?", ":", ";", "”", "’", ")", "]", "…"]

    /// `string` with each replacement's text in place of its UTF-16 range.
    /// The ranges are in order and don't overlap.
    private static func replacing(_ replacements: [(range: Range<Int>, text: String)], in string: String) -> String {
        var result = ""
        var position = 0
        for replacement in replacements where replacement.range.lowerBound >= position {
            result += RubyReadingUnits.substring(of: string, utf16Range: position..<replacement.range.lowerBound)
            result += replacement.text
            position = replacement.range.upperBound
        }
        return result + RubyReadingUnits.substring(of: string, utf16Range: position..<string.utf16.count)
    }
}
