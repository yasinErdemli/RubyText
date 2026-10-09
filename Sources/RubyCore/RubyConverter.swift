import Foundation

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
/// markup supplies your own readings where the automatic ones are wrong.
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

    /// `markup` written out as `transcription` says: kanji become their
    /// readings, and kana the script's kana. Romaji put spaces between
    /// words and turn Japanese punctuation into Latin.
    ///
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .hiragana)  // きょうはコーヒーをのんだ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .katakana)  // キョウハコーヒーヲノンダ。
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .romaji)    // kyō wa kōhī o nonda.
    ///     converter.convert("今日はコーヒーを飲んだ。", to: .romaji(system: .nippon))
    ///     // kyô wa kôhî wo nonda.
    ///
    /// Words without a known reading, such as kanji without an analyzer,
    /// stay as they're written.
    public func convert(_ markup: String, to transcription: RubyTranscription) -> String {
        content(for: markup).transcribed(to: transcription).string
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
    /// - Parameters:
    ///   - markup: The text, with readings you supply in `{base|reading}`
    ///     markup.
    ///   - script: The script readings are written in.
    ///   - parentheses: What the readings are put between. Full width, as
    ///     Japanese text writes them, by default.
    public func annotate(_ markup: String, with script: RubyScript, parentheses: (open: String, close: String) = ("（", "）")) -> String {
        content(for: markup).withInlineReadings(in: script, parentheses: parentheses).string
    }

    private func content(for markup: String) -> RubyContent {
        RubyContent.content(for: markup, analyzer: analyzer)
    }
}
