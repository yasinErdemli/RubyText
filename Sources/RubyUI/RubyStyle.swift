import RubyCore
import RubyTransliteration
import SwiftUI

/// Which annotations `RubyText` draws around Japanese text. Furigana by
/// default.
///
/// Combine options as a set; the empty set shows plain text:
///
///     RubyText("日本語を勉強しています。")
///         .rubyStyle([.furigana, .romaji])
///
/// Either one alone sits above the text. Together, furigana are above
/// and romaji below.
///
/// For learners still learning kana, `.kanaRomaji` puts romaji under each
/// kana instead, a beat at a time, and `rubyKanaRomaji(_:)` leaves out
/// the kana they can read:
///
///     RubyText(segments: sentence.segments)
///         .rubyStyle([.furigana, .kanaRomaji])
///         .rubyKanaRomaji(.except(learnedKana))
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
    /// Romaji under each kana, a beat at a time, for learners who can't
    /// read every kana yet: わたしは over wa ta shi wa, きって over ki t
    /// te. Always below the text, so furigana keep their place above it.
    ///
    /// Choose the kana that get them with `rubyKanaRomaji(_:)`. Kanji
    /// have none, since their readings are furigana, and neither has text
    /// written out with `rubyTranscription(_:)` or with inline furigana.
    /// With `.romaji`, which already writes every word, there are none.
    public static let kanaRomaji = RubyStyle(rawValue: 1 << 2)
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
    /// Whether romaji are drawn under each kana, below the text.
    var kanaRomaji = false
}

extension RubyPlacement {
    init(style: RubyStyle, furiganaPosition: RubyFuriganaPosition = .above, transcription: RubyScript? = nil) {
        // Text written in kana or romaji has no kanji to read, and inline
        // furigana are part of the text.
        let furigana = style.contains(.furigana) && furiganaPosition == .above && transcription == nil
        // Romaji text needs no romaji.
        let romaji = style.contains(.romaji) && transcription?.isRomaji != true
        // Kana romaji go under the kana as written: rewritten text has
        // kana of its own, and romaji for every word already say them.
        let rewritten = transcription != nil || style.contains(.furigana) && furiganaPosition == .inline
        let kanaRomaji = style.contains(.kanaRomaji) && !style.contains(.romaji) && !rewritten
        self.init(furigana: furigana, romajiAbove: romaji && !furigana, romajiBelow: romaji && furigana, kanaRomaji: kanaRomaji)
    }
}

/// Which kanji get furigana, so learners only see readings they need.
///
///     RubyText("今日、政府は新しい経済政策を発表した。")
///         .rubyFurigana(.above(.n4))   // readings for 政府, 経済, 政策, 発表
///
/// A reading spanning several kanji, like せいさく over 政策, shows if any
/// of them is unknown. Changing the filter fades readings in and out.
///
/// To decide by word rather than by kanji, give your segments IDs and show
/// chosen words' readings whatever their kanji:
///
///     RubyText(segments: sentence.segments)
///         .rubyFurigana(.except(learnedKanji).showing(wordIDs: wordsStillLearning))
///
/// There, a word still being learned shows all its readings, while the
/// same kanji elsewhere in the text stay bare.
public struct RubyFuriganaFilter: Hashable, Sendable {
    /// The hardest JLPT level the learner knows, if any.
    private var knownLevel: RubyJLPTLevel?
    /// Kanji the learner knows regardless of level.
    private var knownKanji: Set<Character> = []
    /// Words whose readings show whatever their kanji, by ID.
    private var shownWordIDs: Set<String> = []

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

    /// This filter, also showing every reading of the words with `ids`,
    /// which you give their segments as `wordID`, such as words the
    /// learner is still learning or has tapped.
    public func showing(wordIDs ids: some Sequence<String>) -> RubyFuriganaFilter {
        var filter = self
        filter.shownWordIDs.formUnion(ids)
        return filter
    }

    /// Whether to show the reading of `base`, the text it sits over, in
    /// the word with `wordID`. Readings over kana, which only manual
    /// markup creates, always show.
    func showsReading(over base: String, wordID: String? = nil) -> Bool {
        if let wordID, shownWordIDs.contains(wordID) { return true }
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

/// Which kana get romaji under them with `RubyStyle.kanaRomaji`, so
/// learners only see romaji under the kana they can't read yet.
///
///     RubyText(segments: sentence.segments)
///         .rubyStyle([.furigana, .kanaRomaji])
///         .rubyKanaRomaji(.except(["わ", "た", "し"]))   // わたしは: wa under は
///
/// Kana are matched as written, so a learner learns か and カ apart. A
/// kana with a small one after it, such as きゃ, is known when it's listed
/// itself or when each of its kana is. Changing the filter fades romaji in
/// and out, a kana at a time, as furigana fade a kanji at a time; once no
/// kana has romaji, the text gives back the space they took.
public struct RubyKanaRomajiFilter: Hashable, Sendable {
    /// Kana the learner can read, as written.
    private var knownKana: Set<String> = []
    /// Words whose kana have no romaji, by ID.
    private var hiddenWordIDs: Set<String> = []

    /// Romaji under every kana.
    public static let all = RubyKanaRomajiFilter()

    /// Romaji under every kana except `knownKana`, such as the kana a
    /// learner has learned: か, カ, きゃ, っ, ー.
    public static func except(_ knownKana: some Sequence<String>) -> RubyKanaRomajiFilter {
        RubyKanaRomajiFilter(knownKana: Set(knownKana))
    }

    /// This filter, also leaving out the romaji of the words with `ids`,
    /// which you give their segments as `wordID`, such as a word whose
    /// reading is what an exercise asks.
    public func hiding(wordIDs ids: some Sequence<String>) -> RubyKanaRomajiFilter {
        var filter = self
        filter.hiddenWordIDs.formUnion(ids)
        return filter
    }

    /// Whether `kana`, a beat as written, has its romaji under it in the
    /// word with `wordID`.
    func showsRomaji(under kana: String, wordID: String? = nil) -> Bool {
        if let wordID, hiddenWordIDs.contains(wordID) { return false }
        return !isKnown(kana)
    }

    private func isKnown(_ kana: String) -> Bool {
        knownKana.contains(kana) || kana.count > 1 && kana.allSatisfy { knownKana.contains(String($0)) }
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
            ranges = content.readingUnits.map(\.range)
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
///
/// Either way, no line starts with a character Japanese keeps off the
/// start of a line (行頭禁則), such as 。, 」, ー or ゃ, unless the line is
/// too narrow for anything else.
public enum RubyLineBreaking: Hashable, Sendable {
    /// Between phrases, so words stay with their particles and endings
    /// (東京へ, 日本語を) and never split across lines, like
    /// `word-break: auto-phrase` on the web. A phrase longer than a line
    /// still breaks within it. Where that would start a line with 。 or
    /// another character that may not start one, as it can in large
    /// text, that paragraph breaks between characters instead.
    case phrases
    /// Between almost any two characters, following the rules against
    /// starting a line with 。 or ゃ. Each paragraph's last word stays
    /// together, so its last line never holds a single kana (す。),
    /// unless keeping it together would start a line with 。.
    case anywhere

    /// The language the text is set in, which also selects its line
    /// breaking: Japanese with strict line breaking (`lb=strict`) breaks
    /// between characters, never before 。, ゃ or ー (the normal rules
    /// allow ゃ and ー), and the line-word option (`lw=phrase`) breaks
    /// between phrases instead.
    var languageIdentifier: String {
        switch self {
        case .phrases: "ja-u-lw-phrase"
        case .anywhere: "ja-u-lb-strict"
        }
    }

    /// Sets the language of `text`, which selects how its lines break.
    /// Breaking anywhere, `endings` break only between phrases, so they
    /// stay together on a line.
    ///
    /// - Parameters:
    ///   - endings: UTF-16 ranges from `endings(in:)`, found only when
    ///     breaking anywhere.
    ///   - characterBreaking: Paragraphs, by index, that break between
    ///     characters, because breaking as this asks started one of their
    ///     lines with a character that may not start one; see
    ///     `badlyBrokenParagraphs(in:lineStarts:)`.
    func setLanguage(
        of text: inout AttributedString,
        endings: @autoclosure () -> [Range<Int>],
        characterBreaking: Set<Int> = []
    ) {
        func set(_ language: String, in range: Range<Int>) {
            let lower = text.utf16.index(text.startIndex, offsetBy: range.lowerBound)
            let upper = text.utf16.index(lower, offsetBy: range.count)
            text[lower..<upper].languageIdentifier = language
        }
        text.languageIdentifier = languageIdentifier
        if self == .anywhere {
            for ending in endings() { set(Self.phrases.languageIdentifier, in: ending) }
        }
        guard !characterBreaking.isEmpty else { return }
        // The whole paragraph, with its line break: the language at a
        // paragraph's end decides how it breaks.
        for (index, paragraph) in Self.paragraphRanges(in: String(text.characters)).enumerated()
        where characterBreaking.contains(index) {
            set(Self.anywhere.languageIdentifier, in: paragraph)
        }
    }

    /// Whether `character` may start a line. Japanese keeps closing
    /// brackets and quotes, 。、！？・ and other punctuation, iteration
    /// marks, ー and small kana off the start of a line (行頭禁則, from
    /// JIS X 4051), as strict line breaking does.
    static func canStartLine(_ character: Character) -> Bool {
        if lineStartProhibited.contains(character) { return false }
        switch character.unicodeScalars.first?.properties.generalCategory {
        case .closePunctuation?, .finalPunctuation?: return false
        default: return true
        }
    }

    /// Characters that may not start a line, besides closing brackets and
    /// quotes, which are found by their Unicode category.
    private static let lineStartProhibited = Set(
        // Hyphens, dividing punctuation, middle dots, full stops, commas,
        // ellipses, and units that follow a number.
        "‐–〜゠！？‼⁇⁈⁉!?・：；:;･。．.｡、，,､…‥％%℃"
            // Iteration marks and the prolonged sound mark.
            + "ゝゞヽヾ々〻ーｰ"
            // Small kana.
            + "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿｧｨｩｪｫｬｭｮｯ"
    )

    /// The paragraphs of `string`, by index, where a line starts with a
    /// character that may not start one, other than after a line break.
    ///
    /// Breaking between phrases leaves 。 at the start of a line when the
    /// phrase before it is wider than the line: the system then breaks
    /// after the last character that fits, whatever comes next.
    ///
    /// - Parameter lineStarts: Where each line starts, as laid out: its
    ///   paragraph, and its UTF-16 offset in that paragraph.
    static func badlyBrokenParagraphs(in string: String, lineStarts: [(paragraph: Int, offset: Int)]) -> Set<Int> {
        let paragraphs = paragraphRanges(in: string)
        let characters = Array(string)
        var starts = [0]
        for character in characters { starts.append(starts[starts.count - 1] + character.utf16.count) }
        var result: Set<Int> = []
        for (paragraph, offset) in lineStarts where offset > 0 && paragraphs.indices.contains(paragraph) {
            let index = RubyMeasurements.index(of: paragraphs[paragraph].lowerBound + offset, in: starts)
            guard characters.indices.contains(index), !characters[index - 1].isNewline else { continue }
            if !canStartLine(characters[index]) { result.insert(paragraph) }
        }
        return result
    }

    /// The UTF-16 range of each paragraph of `string`, with the line break
    /// that ends it. A line separator (U+2028) breaks a line within its
    /// paragraph, as in text layout.
    static func paragraphRanges(in string: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var lower = 0
        var offset = 0
        for character in string {
            offset += character.utf16.count
            if character.isNewline && character != "\u{2028}" {
                ranges.append(lower..<offset)
                lower = offset
            }
        }
        ranges.append(lower..<offset)
        return ranges
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
    /// The annotations `RubyText` views draw. Furigana by default.
    @Entry var rubyStyle: RubyStyle = .furigana
    /// Which kanji `RubyText` views show furigana for. All by default.
    @Entry var rubyFuriganaFilter = RubyFuriganaFilter.all
    /// Which kana `RubyText` views put romaji under, with
    /// `RubyStyle.kanaRomaji`. All by default.
    @Entry var rubyKanaRomajiFilter = RubyKanaRomajiFilter.all
    /// The script `RubyText` views write furigana in. Hiragana by default.
    @Entry var rubyFuriganaScript = RubyScript.hiragana
    /// Where `RubyText` views put furigana. Above the text by default.
    @Entry var rubyFuriganaPosition = RubyFuriganaPosition.above
    /// How `RubyText` views write their text out, if not as it's written.
    @Entry var rubyTranscription: RubyScript? = nil
    /// The system `RubyText` views write romaji in. Hepburn by default.
    @Entry var rubyRomanization = RubyRomanization.hepburn
    /// Space `RubyText` views draw between words. None by default.
    @Entry var rubySpacing = RubySpacing.none
    /// Where `RubyText` views may break lines. Between phrases by default.
    @Entry var rubyLineBreaking = RubyLineBreaking.phrases
    /// Whether `RubyText` hides readings over numbers written in digits.
    @Entry var rubyDigitReadingsHidden = false
    /// Which readings VoiceOver says in place of the text as written.
    @Entry var rubySpokenReadings = RubySpokenReadings.corrections
}

extension View {
    /// Sets which annotations `RubyText` views in this hierarchy draw:
    /// furigana by default, `[.furigana, .romaji]` for both, or `[]` for
    /// plain text.
    public func rubyStyle(_ style: RubyStyle = .furigana) -> some View {
        environment(\.rubyStyle, style)
    }

    /// Sets which kanji `RubyText` views in this hierarchy show furigana
    /// for, such as `.above(.n4)` to hide readings of N5 and N4 kanji.
    public func rubyFurigana(_ filter: RubyFuriganaFilter) -> some View {
        environment(\.rubyFuriganaFilter, filter)
    }

    /// Sets which kana `RubyText` views in this hierarchy put romaji under
    /// with `RubyStyle.kanaRomaji`, such as `.except(learnedKana)` to leave
    /// out the kana a learner can read.
    public func rubyKanaRomaji(_ filter: RubyKanaRomajiFilter) -> some View {
        environment(\.rubyKanaRomajiFilter, filter)
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
    ///         .rubyRomanization(.nippon)   // Tôkyô e ikô
    ///
    /// Besides romaji systems, `.polivanov` writes readings in Cyrillic and
    /// `.hangul` in Hangul; `RubyRomanization(_:)` takes a style of your
    /// own. It's the only place the system is set: `.romaji` furigana and
    /// `.romaji` transcriptions follow it.
    public func rubyRomanization(_ system: RubyRomanization) -> some View {
        environment(\.rubyRomanization, system)
    }

    /// Sets where `RubyText` views in this hierarchy put furigana: above
    /// the text, or in parentheses after each kanji.
    ///
    ///     RubyText("東京へ行きたい。")
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
    public func rubyTranscription(_ transcription: RubyScript?) -> some View {
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
    /// always spoken in Japanese, and text in kana as it's written. A
    /// `RubyReader` attached to the views reads aloud with the same
    /// readings.
    public func rubySpokenReadings(_ readings: RubySpokenReadings) -> some View {
        environment(\.rubySpokenReadings, readings)
    }
}
