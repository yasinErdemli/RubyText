import RubyCore
import RubyTransliteration
import SwiftUI

/// Which annotations `RubyText` draws around Japanese text.
///
/// Combine options as a set; the empty set shows plain text:
///
///     RubyText("日本語を勉強しています。")
///         .rubyStyle([.furigana, .romaji])
///
/// Either one alone sits above the text. Together, furigana are above
/// and romaji below.
public struct RubyStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Readings of words that contain kanji: above the text, or in
    /// parentheses after the kanji with `rubyFuriganaPosition(.inline)`.
    /// In hiragana unless `rubyFuriganaScript(_:)` sets another script.
    public static let furigana = RubyStyle(rawValue: 1 << 0)
    /// Romaji for every Japanese word: below the text when furigana are
    /// above it, otherwise above it.
    public static let romaji = RubyStyle(rawValue: 1 << 1)
}

/// Where `RubyText` puts furigana.
public enum RubyFuriganaPosition: Hashable, Sendable {
    /// Above the kanji, as ruby.
    case above
    /// In parentheses after the kanji, as part of the text, the way text
    /// without ruby gives readings: 東京（とうきょう）へ行（い）く.
    case inline
}

/// Where `RubyText` draws each kind of annotation, for a style.
struct RubyPlacement: Equatable {
    /// Whether furigana are drawn above the text.
    let furigana: Bool
    /// Whether romaji are drawn above the text, where furigana would be,
    /// or below it.
    let romajiAbove: Bool
    let romajiBelow: Bool
}

extension RubyPlacement {
    init(style: RubyStyle, furiganaPosition: RubyFuriganaPosition = .above, transcription: RubyTranscription? = nil) {
        // Text written in kana or romaji has no kanji to read, and inline
        // furigana are part of the text.
        let furigana = style.contains(.furigana) && furiganaPosition == .above && transcription == nil
        // Romaji text needs no romaji.
        let romaji = style.contains(.romaji) && transcription?.script.isRomaji != true
        self.init(furigana: furigana, romajiAbove: romaji && !furigana, romajiBelow: romaji && furigana)
    }
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
    /// starting a line with 。 or ゃ. Each paragraph's last word stays
    /// together, so its last line never holds a single kana (す。).
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

    /// Sets the language of `text`, which selects how its lines break.
    /// Breaking anywhere, `endings` break only between phrases, so they
    /// stay together on a line.
    ///
    /// - Parameter endings: UTF-16 ranges from `endings(in:)`, found only
    ///   when breaking anywhere.
    func setLanguage(of text: inout AttributedString, endings: @autoclosure () -> [Range<Int>]) {
        text.languageIdentifier = languageIdentifier
        guard self == .anywhere else { return }
        for ending in endings() {
            let lower = text.utf16.index(text.startIndex, offsetBy: ending.lowerBound)
            let upper = text.utf16.index(lower, offsetBy: ending.count)
            text[lower..<upper].languageIdentifier = Self.words.languageIdentifier
        }
    }

    /// The end of each paragraph to keep on one line: its last word, with
    /// the words before it until they hold two letters, and the punctuation
    /// after them. Kept together, a paragraph's last line never holds a
    /// single kana: ます。, not す。, and 好きだ。, not だ。.
    ///
    /// Each ending includes the line break after it, if there is one: the
    /// language only changes where lines break if it reaches the end of the
    /// paragraph.
    static func endings(in content: RubyContent) -> [Range<Int>] {
        let characters = Array(content.string)
        var starts = [0]
        for character in characters { starts.append(starts[starts.count - 1] + character.utf16.count) }
        // Where the word each character belongs to starts.
        var wordStarts = Array(characters.indices)
        for word in content.words {
            let lower = RubyMeasurements.index(of: word.range.lowerBound, in: starts)
            let upper = RubyMeasurements.index(of: word.range.upperBound, in: starts)
            for index in lower..<upper { wordStarts[index] = lower }
        }
        func isLetter(_ character: Character) -> Bool {
            !(character.isPunctuation || character.isSymbol || character.isWhitespace)
        }

        var paragraphs: [Range<Int>] = []
        var lower = 0
        for (index, character) in characters.enumerated() where character.isNewline {
            paragraphs.append(lower..<index)
            lower = index + 1
        }
        paragraphs.append(lower..<characters.count)

        return paragraphs.compactMap { paragraph in
            var start = paragraph.upperBound
            var letters = 0
            while letters < 2, let last = characters[paragraph.lowerBound..<start].lastIndex(where: isLetter) {
                start = max(wordStarts[last], paragraph.lowerBound)
                letters += characters[start...last].count(where: isLetter)
            }
            guard start < paragraph.upperBound else { return nil }
            return starts[start]..<starts[min(paragraph.upperBound + 1, characters.count)]
        }
    }
}

extension EnvironmentValues {
    /// The annotations `RubyText` views draw. Plain text by default.
    @Entry var rubyStyle: RubyStyle = []
    /// Which kanji `RubyText` views show furigana for. All by default.
    @Entry var rubyFuriganaFilter = RubyFuriganaFilter.all
    /// The script `RubyText` views write furigana in. Hiragana by default.
    @Entry var rubyFuriganaScript = RubyScript.hiragana
    /// Where `RubyText` views put furigana. Above the text by default.
    @Entry var rubyFuriganaPosition = RubyFuriganaPosition.above
    /// How `RubyText` views write their text out, if not as it's written.
    @Entry var rubyTranscription: RubyTranscription? = nil
    /// The system `RubyText` views write romaji in. Hepburn by default.
    @Entry var rubyRomanization = RubyRomanization.hepburn
    /// Space `RubyText` views draw between words. None by default.
    @Entry var rubySpacing = RubySpacing.none
    /// Where `RubyText` views may break lines. Between words by default.
    @Entry var rubyLineBreaking = RubyLineBreaking.words
    /// Whether `RubyText` hides readings over numbers written in digits.
    @Entry var rubyDigitReadingsHidden = false
    /// Which readings VoiceOver says in place of the text as written.
    @Entry var rubySpokenReadings = RubySpokenReadings.corrections
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

    /// Sets the script `RubyText` views in this hierarchy write furigana
    /// in: トウキョウ over 東京 for `.katakana`, and kan over 感 for
    /// `.romaji`.
    ///
    /// In hiragana, the default, readings you supply in markup keep the
    /// kana you wrote them in: {本気|マジ}.
    public func rubyFuriganaScript(_ script: RubyScript) -> some View {
        environment(\.rubyFuriganaScript, script)
    }

    /// Sets the system `RubyText` views in this hierarchy write romaji in,
    /// wherever they show: as annotations, as furigana, inline, or as the
    /// whole text.
    ///
    ///     RubyText("東京へ行こう。")
    ///         .rubyStyle(.romaji)
    ///         .rubyRomanization(.nippon)   // tôkyô e ikô
    ///
    /// A transcription or furigana script naming its own system, such as
    /// `.romaji(system: .passport)`, uses that one instead, as a font
    /// naming its design ignores `fontDesign(_:)`.
    public func rubyRomanization(_ system: RubyRomanization) -> some View {
        environment(\.rubyRomanization, system)
    }

    /// Sets where `RubyText` views in this hierarchy put furigana: above
    /// the text, or in parentheses after each kanji.
    ///
    ///     RubyText("東京へ行きたい。")
    ///         .rubyStyle()
    ///         .rubyFuriganaPosition(.inline)   // 東京（とうきょう）へ行（い）きたい。
    ///
    /// Inline readings are part of the text, so selecting and copying
    /// includes them. Romaji, if shown, move above the text.
    public func rubyFuriganaPosition(_ position: RubyFuriganaPosition) -> some View {
        environment(\.rubyFuriganaPosition, position)
    }

    /// Writes the text of `RubyText` views in this hierarchy out in
    /// hiragana, katakana, or romaji, or as it's written for `nil`, like
    /// `textCase(_:)` does for case.
    ///
    ///     RubyText("今日はコーヒーを飲んだ。")
    ///         .rubyTranscription(.hiragana)   // きょうはコーヒーをのんだ。
    ///     RubyText("今日はコーヒーを飲んだ。")
    ///         .rubyTranscription(.romaji)     // kyō wa kōhī o nonda.
    ///
    /// Kanji become their readings, so furigana have nothing left to
    /// annotate; romaji still show over kana. Selecting and copying gives
    /// the transcribed text, and word details, word colors, and read-aloud
    /// emphasis follow each word to where it moved.
    ///
    /// Kana text is easier to read with spaces between phrases, as
    /// children's books write it (分かち書き): with `rubySpacing(_:)`, it
    /// gets real ideographic spaces, as wide as the spacing asks, which
    /// copy with the text. Lines then break mostly at the spaces, since
    /// without kanji, the system finds phrases poorly.
    ///
    ///     RubyText("今日はコーヒーを飲んだ。")
    ///         .rubyTranscription(.hiragana)
    ///         .rubySpacing(.phrases)          // きょうは　コーヒーを　のんだ。
    public func rubyTranscription(_ transcription: RubyTranscription?) -> some View {
        environment(\.rubyTranscription, transcription)
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

    /// Sets which readings VoiceOver says in place of the text as written
    /// in `RubyText` views in this hierarchy, and in word details.
    ///
    /// By default, VoiceOver says the readings a voice is most likely to
    /// get wrong as the views show them: yours, such as {宇宙|そら}, and
    /// ones rules or the model chose. Pass `.all` to have it say every
    /// reading as furigana show it, or `[]` to leave reading to the voice.
    ///
    ///     RubyText("{宇宙|そら}を見上げた")   // VoiceOver: そらをみあげた
    ///
    /// Braille displays still show the text as written. Text in romaji is
    /// always spoken in Japanese, and text in kana as it's written. Set the
    /// same readings on a `RubyReader` to read aloud alike.
    public func rubySpokenReadings(_ readings: RubySpokenReadings) -> some View {
        environment(\.rubySpokenReadings, readings)
    }
}
