import Foundation
import RubyTransliteration

/// Writes Japanese text out in kana or romaji, or with each kanji's
/// reading in parentheses after it, as plain strings: for search, sharing,
/// or anywhere that isn't a view.
///
///     let converter = RubyConverter(analyzer: analyzer)
///     converter.convert("感じ取れたら手を繋ごう", to: .hiragana)
///     // かんじとれたらてをつなごう
///     converter.convert("感じ取れたら手を繋ごう", to: .romaji)
///     // kanjitoretara te o tsunagō
///     converter.annotate("感じ取れたら手を繋ごう", with: .hiragana)
///     // 感（かん）じ取（と）れたら手（て）を繋（つな）ごう
///
/// The strings are what `RubyText` shows with `rubyTranscription(_:)` and
/// `rubyFuriganaPosition(.inline)`, with the same analyzer. `{base|reading}`
/// markup in a literal, or in `RubyString(markup:)`, supplies your own
/// readings where the automatic ones are wrong.
public struct RubyConverter: Sendable {
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

    /// `string` written out in `script`: kanji become their readings, and
    /// kana the script's kana. Romaji put spaces between words and turn
    /// Japanese punctuation into Latin.
    ///
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .hiragana)  // きょうはコーヒーをのんだ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .katakana)  // キョウハコーヒーヲノンダ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .romaji)    // kyō wa kōhī o nonda.
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .romaji, romanization: .nippon)
    ///     // kyô wa kôhî wo nonda.
    ///
    /// A literal can give readings with `{base|reading}` markup or
    /// interpolation; for markup you load at run time, pass
    /// `RubyString(markup:)`. Words without a known reading, such as kanji
    /// without an analyzer, stay as they're written.
    public func convert(_ string: RubyString, to script: RubyScript, romanization: RubyRomanization = .hepburn) -> String {
        content(for: string).transcribed(to: script.resolved(romanization)).string
    }

    /// `text` written out in `script`, read as it's written: markup in it
    /// isn't read.
    @_disfavoredOverload
    public func convert(_ text: some StringProtocol, to script: RubyScript, romanization: RubyRomanization = .hepburn) -> String {
        convert(RubyString(text: String(text)), to: script, romanization: romanization)
    }

    /// `string` with the reading of each kanji in parentheses after it, in
    /// `script`; everything else as it's written.
    ///
    ///     converter.annotate("東京へ行きたい。", with: .hiragana)  // 東京（とうきょう）へ行（い）きたい。
    ///     converter.annotate("東京へ行きたい。", with: .romaji)    // 東京（tōkyō）へ行（i）きたい。
    ///
    /// Readings you supply in katakana keep it in `.hiragana`: `{本気|マジ}`
    /// is 本気（マジ）.
    ///
    /// - Parameters:
    ///   - string: The text, with any readings you give it.
    ///   - script: The script readings are written in.
    ///   - romanization: The system romaji are written in.
    ///   - parentheses: What the readings are put between. Full width, as
    ///     Japanese text writes them, by default.
    public func annotate(
        _ string: RubyString,
        with script: RubyScript,
        romanization: RubyRomanization = .hepburn,
        parentheses: (open: String, close: String) = ("（", "）")
    ) -> String {
        content(for: string).withInlineReadings(in: script.resolved(romanization), parentheses: parentheses).string
    }

    /// `text`, read as it's written, with the reading of each kanji in
    /// parentheses after it: markup in it isn't read.
    @_disfavoredOverload
    public func annotate(
        _ text: some StringProtocol,
        with script: RubyScript,
        romanization: RubyRomanization = .hepburn,
        parentheses: (open: String, close: String) = ("（", "）")
    ) -> String {
        annotate(RubyString(text: String(text)), with: script, romanization: romanization, parentheses: parentheses)
    }

    private func content(for string: RubyString) -> RubyContent {
        RubyContent.content(for: string, analyzer: analyzer)
    }
}
