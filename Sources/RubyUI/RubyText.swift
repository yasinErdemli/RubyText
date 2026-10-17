import Accessibility
import FoundationModels
@_spi(Experiments) import RubyCore
import RubyTransliteration
import SwiftUI
import Synchronization

/// Japanese text that can show furigana or romaji above its words, or
/// furigana above and romaji below.
///
/// Use it like `Text`. Furigana show by default; choose other annotations
/// with `rubyStyle(_:)` on it or any parent view. Readings are generated on
/// device; supply your own with `{base|reading}` markup where the automatic
/// one is wrong:
///
///     RubyText("{今日|きょう}は日本語を勉強しています。")
///         .font(.title)
///         .textSelection(.enabled)
///         .rubyStyle([.furigana, .romaji])
///
/// Or give readings in code with string interpolation, where text you
/// interpolate, such as from people using your app, can't add readings:
///
///     RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
///
/// As `Text` reads Markdown, markup is only read where you opt in: in a
/// literal, or with `init(markup:)` for markup you load at run time. A
/// `String` you pass is shown as written:
///
///     RubyText(comment)          // as written, with readings found for it
///     RubyText(markup: json)     // {base|reading} markup read
///
/// For learners still learning kana, `.kanaRomaji` puts romaji under each
/// kana instead, a beat at a time, and `rubyKanaRomaji(_:)` leaves out
/// the kana they can read, so the romaji fade as they learn them.
///
/// Readings can also be written into the text itself: in parentheses
/// after each kanji with `rubyFuriganaPosition(.inline)`, or as the whole
/// text in hiragana, katakana, or romaji with `rubyTranscription(_:)`.
/// `rubyFuriganaScript(_:)` writes furigana in katakana or romaji.
///
/// Pass `RubySegment`s directly to show readings from your own data, with
/// no on-device analysis:
///
///     RubyText(segments: mySegments)
///
/// Like `Text`, it wraps to the width it's offered. Unlike `Text`, it
/// takes the height of all its lines even where it's offered less, as in
/// a stack that has run out of room, rather than showing the lines that
/// fit; `lineLimit(_:)` cuts it short.
///
/// Changing the style animates: annotations fade in or out, and the line
/// spacing and letter spacing they need ease to their new values. Text
/// rewritten in another script rolls into the new text glyph by glyph,
/// like `numericText()`.
///
/// Furigana use the secondary foreground style and romaji, under words or
/// under kana, the tertiary one, so they're quieter than the text by
/// default and can be colored with the standard modifiers:
///
///     .foregroundStyle(.primary, .red, .blue)      // red furigana, blue romaji
///     .foregroundStyle(.primary, .primary, .primary) // all in the text color
///
/// The word being read aloud uses `.tint`, and its highlight uses
/// `backgroundStyle` when one is set.
///
/// Attach a `RubyReader` with `rubyReader(_:)` to emphasize each word as it's
/// read aloud, styled with `rubyEmphasis(_:)`.
///
/// Readings come from the analyzer you set with `rubyAnalyzer(_:)`, such as
/// RubyMeCab's `RubyMeCabAnalyzer` with the IPAdic or UniDic dictionary
/// your app bundles, or your own; without one, only readings in
/// `{base|reading}` markup show. Add `rubyModelReadings()` to have a
/// language model read words whose reading depends on their meaning.
///
/// Short text is analyzed as the view appears. Longer text, over 200
/// UTF-16 code units, appears at once with the readings its markup gives,
/// and is analyzed off the main actor, its readings fading in when they're
/// ready, so a long passage doesn't hold up the interface.
///
/// Annotations are drawn by `RubyRenderer` and aren't part of the text
/// content, so selection and copy only see the text, as written or as
/// rewritten. VoiceOver reads the text once, saying readings voices
/// would likely get wrong as furigana show them; see
/// `rubySpokenReadings(_:)`. With word details or a tap action, each word
/// is also an accessibility action, so VoiceOver users swipe up or down
/// to a word and double-tap for it.
public struct RubyText: View {
    private enum Input {
        case string(RubyString)
        case segments([RubySegment])
    }
    private let input: Input

    @Environment(\.rubyAnalyzer) private var analyzer
    @Environment(\.rubyStyle) private var style
    @Environment(\.rubyFuriganaScript) private var furiganaScript
    @Environment(\.rubyFuriganaPosition) private var furiganaPosition
    @Environment(\.rubyTranscription) private var transcription
    @Environment(\.rubyRomanization) private var romanization
    @Environment(\.rubyFuriganaFilter) private var furiganaFilter
    @Environment(\.rubyKanaRomajiFilter) private var kanaRomajiFilter
    @Environment(\.rubyDigitReadingsHidden) private var digitReadingsHidden
    @Environment(\.rubySpacing) private var spacing
    @Environment(\.rubyWordColoring) private var wordColoring
    @Environment(\.rubyWordWeights) private var wordWeights
    @Environment(\.rubyDictionary) private var dictionary
    @Environment(\.rubyModelReadings) private var modelUpdates
    @Environment(\.rubyModelOptions) private var modelOptions
    @Environment(\.rubySpokenReadings) private var spokenReadings
    @Environment(\.rubyShowsWordDetails) private var showsWordDetails
    @Environment(\.rubyWordTapAction) private var wordTapAction
    @Environment(\.rubyReader) private var reader
    /// Content for text too long to analyze as the view appears, once
    /// it's analyzed, and the input it's for.
    @State private var analyzedContent: (key: AnalysisKey, content: RubyContent)?
    /// Content with the model's readings, once it has answered, and the
    /// input it's for.
    @State private var modelContent: (key: ModelKey, content: RubyContent)?
    /// The tapped word whose details are showing, and where it is.
    @State private var selectedWord: RubyWordInfo?
    @State private var selectedRect = CGRect.zero
    /// Paragraphs that break between characters, as breaking between
    /// phrases started one of their lines with 。 or the like.
    @State private var lineBreakFallback: RubyLineBreakFallback?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates ruby text from a string literal, with readings you give in
    /// it:
    ///
    ///     RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
    ///     RubyText("{今日|きょう}は晴れ。")
    ///
    /// See `RubyString` for what it can hold. Unlike `Text`, a literal isn't
    /// localized; for localized text, pass a `LocalizedStringResource`, such
    /// as a symbol your String Catalog generates.
    public init(_ string: RubyString) {
        input = .string(string)
    }

    /// Creates ruby text from a localized string, whose translations can
    /// use `{base|reading}` markup:
    ///
    ///     RubyText(.welcome)
    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) {
        input = .string(RubyString(markup: String(localized: resource)))
    }

    /// Creates ruby text from a string, shown as written, as `Text` shows a
    /// string: markup in it isn't read, so text from people using your app
    /// can't add readings.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        input = .string(RubyString(text: String(content)))
    }

    /// Creates ruby text from a string, shown as written, even a literal:
    /// markup in it isn't read.
    public init(verbatim content: String) {
        input = .string(RubyString(text: content))
    }

    /// Creates ruby text from `{base|reading}` markup you load at run time,
    /// such as from JSON:
    ///
    ///     RubyText(markup: "{宇宙|そら}を見上げた。")
    public init(markup: String) {
        input = .string(RubyString(markup: markup))
    }

    /// Creates ruby text from segments you supply, such as readings from
    /// your own data store, with no on-device analysis.
    public init(segments: [RubySegment]) {
        input = .segments(segments)
    }

    public var body: some View {
        // The dictionary's readings show until the model's arrive.
        let analyzed: RubyContent = if let modelContent, modelContent.key == modelKey {
            modelContent.content
        } else {
            dictionaryContent
        }
        let content = rewritten(analyzed)
        let speech = content.speech(spokenReadings)
        let placement = RubyPlacement(style: style, furiganaPosition: furiganaPosition, transcription: transcription)
        let kanaRomajiVisibility = placement.kanaRomaji ? kanaRomajiVisibility(in: content) : .zero
        RubyTextContent(
            content: content,
            furigana: placement.furigana ? 1 : 0,
            romajiAbove: placement.romajiAbove ? 1 : 0,
            romajiBelow: placement.romajiBelow ? 1 : 0,
            // Once no kana has romaji, the space below the text goes too.
            kanaRomaji: kanaRomajiVisibility.isZero ? 0 : 1,
            readingVisibility: readingVisibility(in: content),
            romajiVisibility: romajiVisibility(in: content),
            kanaRomajiVisibility: kanaRomajiVisibility,
            wordGaps: wordGaps(in: content),
            // Computed here, not inside the animated content view, so
            // style transitions don't re-run vocabulary and JLPT lookups
            // on every frame.
            textColors: RubyTextContent.coloredRanges(wordColoring.text, in: content),
            backgroundColors: RubyTextContent.coloredRanges(wordColoring.background, in: content),
            textWeights: RubyTextContent.weightedRanges(wordWeights, in: content),
            speech: speech,
            accessibilityWords: showsWordDetails || wordTapAction != nil
                ? RubyTextContent.accessibilityWords(in: content, speech: speech)
                : [],
            // Word details describe the word as written.
            selectedRange: selectedWord.map { content.range(fromOriginal: $0.range) },
            selectedWord: $selectedWord,
            selectedRect: $selectedRect,
            lineBreakFallback: $lineBreakFallback
        )
        // All its lines, for the width it's offered, even offered less
        // height. Text offered less shows the lines that fit, but it's drawn
        // in more room than that, the room annotations have around it, so
        // one more line was drawn below the text, over whatever is there.
        // `lineLimit(_:)` is what cuts it short.
        .fixedSize(horizontal: false, vertical: true)
        .popover(item: $selectedWord, attachmentAnchor: .rect(.rect(selectedRect))) { word in
            RubyWordDetailView(word: word, dictionary: dictionary)
                .presentationCompactAdaptation(.popover)
        }
        // Annotations slide and lines move apart, so with Reduce Motion the
        // style switches without animating.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: style)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: furiganaScript)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: furiganaPosition)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: transcription)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: romanization)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: furiganaFilter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: kanaRomajiFilter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: digitReadingsHidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: spacing)
        .task(id: analysisKey) {
            await analyze()
        }
        .task(id: modelKey) {
            await loadModelReadings()
        }
        // An attached reader reads with this view's analyzer and spoken
        // readings, so it finds the same words and says what VoiceOver says.
        .onChange(of: readerSettings, initial: true) {
            reader?.adopt(analyzer: analyzer, spokenReadings: spokenReadings)
        }
    }

    /// What an attached reader takes from this view.
    private struct ReaderSettings: Equatable {
        let reader: ObjectIdentifier?
        let analyzer: AnyHashable?
        let spokenReadings: RubySpokenReadings
    }

    private var readerSettings: ReaderSettings {
        ReaderSettings(reader: reader.map(ObjectIdentifier.init), analyzer: analyzer.map { AnyHashable($0) }, spokenReadings: spokenReadings)
    }

    /// `content` as the transcription or inline furigana write it.
    private func rewritten(_ content: RubyContent) -> RubyContent {
        if let transcription {
            // Spacing in kana text is real spaces, so lines break at them.
            return content.transcribed(to: transcription.resolved(romanization), spacedAt: spacing.boundaries(in: content))
        }
        if style.contains(.furigana), furiganaPosition == .inline {
            return content.withInlineReadings(in: furiganaScript.resolved(romanization))
        }
        return content
    }

    /// The text with the analyzer's readings, and the rules', if it has
    /// them yet.
    ///
    /// Cached per string or segment array, so this is cheap after the
    /// first time. Short text is analyzed right away, which takes about a
    /// millisecond. Longer text shows with only the readings it gives
    /// until `analyze()` has analyzed it off the main actor.
    private var dictionaryContent: RubyContent {
        switch input {
        case .segments(let segments):
            return .content(for: segments)
        case .string(let string):
            if let analyzedContent, analyzedContent.key == analysisKey {
                return analyzedContent.content
            }
            return RubyContent.immediateContent(for: string, analyzer: analyzer)
                ?? .content(for: string, analyzer: nil)
        }
    }

    /// What the analyzer's readings depend on: the text and the analyzer.
    private struct AnalysisKey: Equatable {
        let string: RubyString?
        let analyzer: AnyHashable?
    }

    private var analysisKey: AnalysisKey {
        let string: RubyString? = if case .string(let string) = input { string } else { nil }
        return AnalysisKey(string: string, analyzer: analyzer.map { AnyHashable($0) })
    }

    /// Analyzes text too long to analyze as the view appears, off the main
    /// actor, and shows its readings when they're ready.
    private func analyze() async {
        let key = analysisKey
        guard let string = key.string, RubyContent.immediateContent(for: string, analyzer: analyzer) == nil else { return }
        let content = await RubyContent.analyzing(string, analyzer: analyzer)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            analyzedContent = (key, content)
        }
    }

    /// What the model's readings depend on: the markup, the analyzer, and
    /// whether they're on and how they update.
    private struct ModelKey: Equatable {
        let string: RubyString?
        let analyzer: AnyHashable?
        let updates: RubyModelReadingUpdates?
        let options: RubyModelOptions
    }

    private var modelKey: ModelKey {
        let string: RubyString? = if case .string(let string) = input { string } else { nil }
        return ModelKey(string: string, analyzer: analyzer.map { AnyHashable($0) }, updates: modelUpdates, options: modelOptions)
    }

    /// Asks the model about words whose reading depends on their meaning,
    /// and shows its readings as the updates option says. Segments you
    /// supply are shown as they are.
    private func loadModelReadings() async {
        let key = modelKey
        guard let updates = key.updates, let string = key.string, analyzer != nil, key.options.isAvailable else { return }
        let onEachReading: (@Sendable (RubyContent) async -> Void)? = if updates == .asAnswered {
            { @MainActor content in
                guard !Task.isCancelled else { return }
                modelContent = (key, content)
            }
        } else {
            nil
        }
        let content = await RubyContent.content(
            for: string,
            analyzer: analyzer,
            chooser: RubyLanguageModelChooser(options: key.options),
            onEachReading: onEachReading
        )
        guard !Task.isCancelled else { return }
        modelContent = (key, content)
    }

    /// Whether the filter shows each furigana reading, in content order.
    /// Always one value per reading, even when all show, so animating
    /// between filters interpolates each reading from its old visibility.
    private func readingVisibility(in content: RubyContent) -> RubyAnimatableVector {
        RubyAnimatableVector(values: content.words.flatMap { word in
            word.furigana.map { reading in
                let base = RubyReadingUnits.substring(of: content.string, utf16Range: reading.range)
                if digitReadingsHidden && Self.isDigitNumber(base) { return 0 }
                return furiganaFilter.showsReading(over: base, wordID: word.wordID) ? 1 : 0
            }
        })
    }

    /// Whether each romaji word shows, in content order. Romaji hide over
    /// numbers in digits along with their furigana, so a number shows both
    /// readings or neither.
    private func romajiVisibility(in content: RubyContent) -> RubyAnimatableVector {
        RubyAnimatableVector(values: content.romajiWords(in: romanization).map { word in
            let base = RubyReadingUnits.substring(of: content.string, utf16Range: word.range)
            return digitReadingsHidden && Self.isDigitNumber(base) ? 0 : 1
        })
    }

    /// Whether each kana's romaji shows under it, in content order, one
    /// value per kana, so each fades on its own as the filter changes.
    private func kanaRomajiVisibility(in content: RubyContent) -> RubyAnimatableVector {
        RubyAnimatableVector(values: content.kanaRomaji(in: romanization).map { beat in
            kanaRomajiFilter.showsRomaji(under: beat.kana, wordID: beat.wordID) ? 1 : 0
        })
    }

    /// Whether `text` is a number written in digits, half or full width,
    /// such as 2026年 or ３日. Kanji numerals are numeric but not decimal.
    static func isDigitNumber(_ text: String) -> Bool {
        text.unicodeScalars.first?.properties.numericType == .decimal
    }

    /// The space after each UTF-16 offset in the text, as a fraction of the
    /// font size. One value per offset, so switching between word and
    /// phrase spacing animates each space separately.
    private func wordGaps(in content: RubyContent) -> RubyAnimatableVector {
        // Transcribed text has real spaces: romaji between words, and kana
        // wherever the spacing puts them.
        guard transcription == nil else { return .zero }
        // Words and phrases are found in the text as written.
        let boundaries = spacing.boundaries(in: content.original ?? content).map(content.offset(fromOriginal:))
        guard !boundaries.isEmpty else { return .zero }
        var values = [Double](repeating: 0, count: content.string.utf16.count + 1)
        for offset in boundaries { values[offset] = spacing.width }
        return RubyAnimatableVector(values: values)
    }
}

extension EnvironmentValues {
    /// Finds words and readings for `RubyText` views, if anything does.
    @Entry var rubyAnalyzer: (any RubyAnalyzer)? = nil
    /// How `RubyText` views show readings Apple's on-device model chooses
    /// for words whose reading depends on their meaning, or `nil` not to
    /// ask it.
    @Entry var rubyModelReadings: RubyModelReadingUpdates? = nil
    /// Which model is asked for readings by meaning, and how.
    @Entry var rubyModelOptions = RubyModelOptions.standard
}

/// When `RubyText` shows the readings a language model chooses.
public enum RubyModelReadingUpdates: Hashable, Sendable {
    /// All together, once the model has answered about every word in the
    /// text, so the text changes once. The default.
    case allAtOnce
    /// Each as soon as the model answers about its word, so a long text
    /// corrects itself while the model works through it.
    case asAnswered
}

extension View {
    /// Sets the analyzer `RubyText` views in this hierarchy use to find
    /// words and readings. Set it once, near the root of your app, such as
    /// RubyMeCab's analyzer with a dictionary your app bundles:
    ///
    ///     let analyzer = RubyMeCabAnalyzer(
    ///         dictionary: Bundle.main.url(forResource: "ipadic", withExtension: "bundle")!
    ///     )
    ///
    ///     ContentView()
    ///         .rubyAnalyzer(analyzer)
    ///
    /// Any type conforming to `RubyAnalyzer` works, such as one on Apple's
    /// built-in tokenizer or a server. Without an analyzer, only readings
    /// in `{base|reading}` markup show.
    /// A `RubyReader` attached to the views reads with the same analyzer.
    public func rubyAnalyzer(_ analyzer: some RubyAnalyzer) -> some View {
        environment(\.rubyAnalyzer, analyzer)
    }

    /// Has a language model read words whose reading depends on their
    /// meaning in `RubyText` views in this hierarchy: 辛い is からい for
    /// spicy food and つらい for a hard parting, 人気 is にんき for
    /// popularity and ひとけ for people around.
    ///
    /// The dictionary reads such words the same way in every sentence.
    /// With this on, text first shows the dictionary's readings, then
    /// updates the ones the model judges are meant differently. Only words
    /// on a built-in list are asked about, and the model only chooses among
    /// that list's readings. Where the model isn't available or fails, the
    /// dictionary's readings stay.
    ///
    /// Apple's on-device model answers by default: private, offline and
    /// free. Pass another FoundationModels `LanguageModel` to `model` to
    /// have it answer instead:
    ///
    ///     RubyText(text)
    ///         .rubyModelReadings(model: PrivateCloudComputeLanguageModel())
    ///
    /// Private Cloud Compute is Apple's larger model, only for apps with
    /// the `com.apple.developer.private-cloud-compute` entitlement: without
    /// it, the system stops the app as soon as the model is asked. A model
    /// from another provider works once it conforms to `LanguageModel`; it
    /// must support guided generation, as RubyText limits its answer to
    /// the listed meanings with a schema. Models off the device receive
    /// each sentence they're asked about.
    ///
    /// The model answers about one word at a time, saying in a few words
    /// what it means before choosing, with the sentences around it: about
    /// a second for each word with the on-device model on a recent iPhone,
    /// so a long text with many such words takes a while. Pass
    /// `.asAnswered` to `updates` to change each reading as soon as its
    /// answer comes rather than all together at the end.
    ///
    /// Readings you supply with `{base|reading}` markup or as segments are
    /// never changed.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether to ask the model.
    ///   - updates: Whether readings change all together or each as soon
    ///     as it's answered.
    ///   - model: The model that answers.
    public func rubyModelReadings(
        _ isEnabled: Bool = true,
        updates: RubyModelReadingUpdates = .allAtOnce,
        model: any LanguageModel = SystemLanguageModel.default
    ) -> some View {
        rubyModelReadings(isEnabled, updates: updates, options: RubyModelOptions(model: model))
    }

    /// Has a language model read words by meaning as `options` ask it, to
    /// compare ways of asking.
    @_spi(Experiments) public func rubyModelReadings(
        _ isEnabled: Bool = true,
        updates: RubyModelReadingUpdates = .allAtOnce,
        options: RubyModelOptions
    ) -> some View {
        environment(\.rubyModelReadings, isEnabled ? updates : nil)
            .environment(\.rubyModelOptions, options)
    }
}

/// Draws `RubyText` with each kind of annotation at a strength from 0
/// (hidden, no space reserved) to 1 (fully shown). SwiftUI interpolates the
/// strengths when the style changes, so everything eases into place.
@Animatable
private struct RubyTextContent: View {
    @AnimatableIgnored let content: RubyContent
    var furigana: CGFloat
    /// Romaji above the text, where furigana would be, and below it.
    /// Switching between furigana and romaji alone crossfades them above.
    var romajiAbove: CGFloat
    var romajiBelow: CGFloat
    /// Romaji under each kana, below the text.
    var kanaRomaji: CGFloat
    var readingVisibility: RubyAnimatableVector
    var romajiVisibility: RubyAnimatableVector
    var kanaRomajiVisibility: RubyAnimatableVector
    var wordGaps: RubyAnimatableVector
    /// Precomputed by `RubyText`, so word coloring doesn't re-run its
    /// lookups on every frame of a style animation.
    @AnimatableIgnored let textColors: [RubyColoredRange]
    @AnimatableIgnored let backgroundColors: [RubyColoredRange]
    @AnimatableIgnored let textWeights: [RubyWeightedRange]
    /// What VoiceOver says in place of parts of the text.
    @AnimatableIgnored let speech: [RubySpokenText]
    /// The words VoiceOver users can choose, if words can be tapped.
    @AnimatableIgnored let accessibilityWords: [RubyAccessibilityWord]

    @AnimatableIgnored @Environment(\.rubyReader) private var reader
    @AnimatableIgnored @Environment(\.rubyEmphasis) private var emphasisOptions
    @AnimatableIgnored @Environment(\.rubyLineBreaking) private var lineBreaking
    @AnimatableIgnored @Environment(\.truncationMode) private var truncationMode
    @AnimatableIgnored @Environment(\.rubySpacing) private var spacing
    @AnimatableIgnored @Environment(\.rubyShowsWordDetails) private var showsWordDetails
    @AnimatableIgnored @Environment(\.rubyWordTapAction) private var wordTapAction
    @AnimatableIgnored @Environment(\.rubyFuriganaScript) private var furiganaScript
    @AnimatableIgnored @Environment(\.rubyRomanization) private var romanization
    @AnimatableIgnored @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AnimatableIgnored @Environment(\.font) private var font
    // Carries Dynamic Type and other traits needed to resolve `font`.
    @AnimatableIgnored @Environment(\.fontResolutionContext) private var fontResolutionContext
    /// The range of the word whose details are showing, to highlight it.
    /// Passed as a value so the highlight updates when the popover closes.
    @AnimatableIgnored let selectedRange: Range<Int>?
    /// The tapped word whose details are showing, and where it is, owned
    /// by `RubyText`.
    @AnimatableIgnored let selectedWord: Binding<RubyWordInfo?>
    @AnimatableIgnored let selectedRect: Binding<CGRect>
    /// Paragraphs that break between characters, as breaking between
    /// phrases started one of their lines with 。 or the like, owned by
    /// `RubyText`.
    @AnimatableIgnored let lineBreakFallback: Binding<RubyLineBreakFallback?>

    private var isTappable: Bool { showsWordDetails || wordTapAction != nil }

    /// How strongly romaji show, wherever they are.
    private var romaji: CGFloat { min(1, romajiAbove + romajiBelow) }

    /// How much of the reserved height annotations take above and below
    /// each line.
    private var above: CGFloat { min(1, furigana + romajiAbove) }
    private var below: CGFloat { min(1, romajiBelow + kanaRomaji) }

    var body: some View {
        let metrics = RubyMetrics(font: font ?? .body, in: fontResolutionContext)
        let lineBreakKey = RubyLineBreakFallback.Key(string: content.string, font: metrics.cacheKey, lineBreaking: lineBreaking)
        let characterBreaking = lineBreakFallback.wrappedValue.flatMap { $0.key == lineBreakKey ? $0.paragraphs : nil } ?? []
        let lineStartCheck = RubyLineStartCheck(
            // Only text with a character that may not start a line can
            // start one with it.
            isEnabled: !content.string.allSatisfy(RubyLineBreaking.canStartLine),
            key: lineBreakKey,
            fallback: lineBreakFallback
        )

        if above == 0 && below == 0 && reader == nil && textColors.isEmpty && backgroundColors.isEmpty
            && textWeights.isEmpty && wordGaps.isZero && content.spaces.isEmpty && !isTappable {
            Text(Self.plainText(content, lineBreaking: lineBreaking, characterBreaking: characterBreaking).speaking(speech))
                .font(metrics.textFont)
                .contentTransition(.numericText())
                .modifier(lineStartCheck)
        } else {
            let layout = RubyLayout(
                measurements: .measurements(
                    for: content,
                    metrics: metrics,
                    furiganaScript: furiganaScript.resolved(romanization),
                    romanization: romanization,
                    weights: textWeights,
                    kanaRomaji: kanaRomaji > 0
                ),
                furigana: furigana,
                romaji: romaji,
                readingVisibility: readingVisibility,
                romajiVisibility: romajiVisibility,
                kanaRomaji: kanaRomaji,
                kanaRomajiVisibility: kanaRomajiVisibility,
                wordGaps: wordGaps,
                fontSize: metrics.fontSize,
                romajiSpacing: metrics.romajiSpacing,
                lineBreaking: lineBreaking,
                characterBreaking: characterBreaking,
                insertedSpaceWidth: spacing.width,
                textColors: textColors,
                backgrounds: backgrounds(),
                weightedMetrics: Dictionary(uniqueKeysWithValues: Set(textWeights.map(\.weight)).map { ($0, metrics.weighted($0)) })
            )

            if let reader {
                // Only tick while this text is the one being read.
                let isReadingThis = reader.text == content.sourceString && reader.isSpeaking
                TimelineView(.animation(paused: !isReadingThis || reader.isPaused)) { _ in
                    annotatedText(layout, metrics: metrics, lineStartCheck: lineStartCheck, emphasis: isReadingThis
                        ? emphasisState(reader: reader, layout: layout)
                        : nil)
                }
            } else {
                annotatedText(layout, metrics: metrics, lineStartCheck: lineStartCheck, emphasis: nil)
            }
        }
    }

    private func annotatedText(
        _ layout: RubyLayout,
        metrics: RubyMetrics,
        lineStartCheck: RubyLineStartCheck,
        emphasis: RubyEmphasisState?
    ) -> some View {
        let above = metrics.reservedHeight * above
        let below = metrics.reservedHeight * below

        return Text(layout.text.speaking(speech))
            .font(metrics.textFont)
            // Text rewritten in another script rolls into the new one, glyph
            // by glyph, letters and kana as well as digits.
            .contentTransition(.numericText())
            .lineSpacing(above + below)
            .padding(.top, above)
            .padding(.bottom, below)
            .textRenderer(RubyRenderer(
                metrics: metrics,
                paragraphs: layout.paragraphs,
                furigana: furigana,
                romajiAbove: romajiAbove,
                romajiBelow: romajiBelow,
                kanaRomaji: kanaRomaji,
                truncationMode: truncationMode,
                emphasis: emphasis
            ))
            // Over a material, such as a popover's glass, foreground styles
            // turn vibrant, and text the renderer draws in them, such as
            // annotations, doesn't show. The text keeps the regular styles.
            .environment(\.backgroundMaterial, nil)
            .modifier(lineStartCheck)
            .modifier(RubyWordTapping(
                isEnabled: isTappable,
                words: accessibilityWords,
                onTap: { point, geometry in
                    tapWord(at: point, in: geometry, layout: layout, metrics: metrics)
                },
                onActivate: { index, geometry in
                    selectWord(index, in: geometry, layout: layout, metrics: metrics)
                }
            ))
    }

    /// Word backgrounds, plus a highlight on the word whose details show.
    private func backgrounds() -> [RubyColoredRange] {
        var ranges = backgroundColors
        if let selection = selectedRange {
            ranges.removeAll { $0.range.overlaps(selection) }
            ranges.append(RubyColoredRange(range: selection, color: .accentColor))
            ranges.sort { $0.range.lowerBound < $1.range.lowerBound }
        }
        return ranges
    }

    // MARK: Word taps

    private func tapWord(at point: CGPoint, in geometry: RubyTextGeometry, layout: RubyLayout, metrics: RubyMetrics) {
        guard let offset = characterOffset(at: point, in: geometry, layout: layout, metrics: metrics),
              let index = content.dictionaryWords.firstIndex(where: { $0.contains(offset) })
        else {
            selectedWord.wrappedValue = nil
            return
        }
        selectWord(index, in: geometry, layout: layout, metrics: metrics)
    }

    /// Reports the dictionary word at `index` to the tap action, and shows
    /// its details.
    private func selectWord(_ index: Int, in geometry: RubyTextGeometry, layout: RubyLayout, metrics: RubyMetrics) {
        guard content.dictionaryWords.indices.contains(index) else { return }
        let range = content.dictionaryWords[index]
        // Details describe the word as written, even in rewritten text,
        // whose words match the original's one to one.
        let source = content.original ?? content
        let word = RubyWordInfo.info(for: source.dictionaryWords[index], in: source, romanization: romanization)
        wordTapAction?(word)
        if showsWordDetails {
            selectedRect.wrappedValue = wordRect(range, in: geometry, layout: layout, metrics: metrics) ?? .zero
            selectedWord.wrappedValue = word
        }
    }

    /// Each dictionary word in `content` with letters in it, named as
    /// VoiceOver says it in the text with `speech`, for word actions.
    fileprivate static func accessibilityWords(in content: RubyContent, speech: [RubySpokenText]) -> [RubyAccessibilityWord] {
        content.dictionaryWords.enumerated().compactMap { index, range in
            let text = RubyReadingUnits.substring(of: content.string, utf16Range: range)
            guard text.contains(where: \.isLetter) else { return nil }
            // What VoiceOver says for the parts of the word it says differently.
            let spoken = speech.filter { range.contains($0.range.lowerBound) }.map {
                RubySpokenText(range: ($0.range.lowerBound - range.lowerBound)..<(min($0.range.upperBound, range.upperBound) - range.lowerBound), text: $0.text)
            }
            return RubyAccessibilityWord(id: index, name: Text(AttributedString(text).speaking(spoken)))
        }
    }

    /// The UTF-16 offset in the text of the character at `point`. A tap on
    /// a word's furigana or romaji counts as a tap on the word.
    private func characterOffset(at point: CGPoint, in geometry: RubyTextGeometry, layout: RubyLayout, metrics: RubyMetrics) -> Int? {
        let point = CGPoint(x: point.x - geometry.origin.x, y: point.y - geometry.origin.y)
        let above = metrics.reservedHeight * above
        let below = metrics.reservedHeight * below
        for (_, line, paragraph, start) in geometry.layout.rubyParagraphLines {
            let bounds = line.typographicBounds.rect
            guard point.y >= bounds.minY - above, point.y < bounds.maxY + below else { continue }
            for run in line {
                let indices = run.characterIndices
                guard indices.count == run.count else { continue }
                for index in 0..<run.count {
                    let box = run[index..<(index + 1)].typographicBounds.rect
                    if box.minX <= point.x, point.x < box.maxX {
                        return layout.offset(start.distance(to: indices[index]), inParagraph: paragraph)
                    }
                }
            }
        }
        return nil
    }

    /// The bounds of `range` and its annotations on the first line it's on,
    /// for the details popover to point at.
    private func wordRect(_ range: Range<Int>, in geometry: RubyTextGeometry, layout: RubyLayout, metrics: RubyMetrics) -> CGRect? {
        for (_, line, paragraph, start) in geometry.layout.rubyParagraphLines {
            var rect = CGRect.null
            for run in line {
                let indices = run.characterIndices
                guard indices.count == run.count else { continue }
                for index in 0..<run.count
                where range.contains(layout.offset(start.distance(to: indices[index]), inParagraph: paragraph)) {
                    rect = rect.union(run[index..<(index + 1)].typographicBounds.rect)
                }
            }
            guard !rect.isNull else { continue }
            let bounds = line.typographicBounds.rect
            let above = metrics.reservedHeight * above
            let below = metrics.reservedHeight * below
            return CGRect(
                x: rect.minX + geometry.origin.x,
                y: bounds.minY - above + geometry.origin.y,
                width: rect.width,
                height: bounds.height + above + below
            )
        }
        return nil
    }

    /// Text without annotations, tagged as Japanese so lines break the
    /// same way as annotated text.
    private static func plainText(_ content: RubyContent, lineBreaking: RubyLineBreaking, characterBreaking: Set<Int>) -> AttributedString {
        var text = AttributedString(content.string)
        lineBreaking.setLanguage(of: &text, endings: RubyLineBreaking.endings(in: content), characterBreaking: characterBreaking)
        return text
    }

    /// The ranges `colors` colors, with neighboring words of the same color
    /// merged so a compound like 日本|語 gets one background.
    fileprivate static func coloredRanges(_ colors: RubyWordColors?, in content: RubyContent) -> [RubyColoredRange] {
        guard let colors else { return [] }
        // Words are colored as written, then wherever rewriting moved them.
        let source = content.original ?? content
        return merged(colors.colors(for: source.words, in: source.string), in: content)
            .map { RubyColoredRange(range: $0.range, color: $0.value) }
    }

    /// The ranges `weights` sets in their own weight, with neighboring
    /// words of the same weight merged.
    fileprivate static func weightedRanges(_ weights: RubyWordWeights?, in content: RubyContent) -> [RubyWeightedRange] {
        guard let weights else { return [] }
        let source = content.original ?? content
        return merged(weights.weights(for: source.words, in: source.string), in: content)
            .map { RubyWeightedRange(range: $0.range, weight: $0.value) }
    }

    /// The range of each word of `content` with a value, one value per
    /// word, merging neighboring words with the same value.
    private static func merged<Value: Equatable>(_ values: [Value?], in content: RubyContent) -> [(range: Range<Int>, value: Value)] {
        var ranges: [(range: Range<Int>, value: Value)] = []
        for (word, value) in zip(content.words, values) {
            guard let value else { continue }
            if let last = ranges.last, last.value == value, last.range.upperBound == word.range.lowerBound {
                ranges[ranges.count - 1].range = last.range.lowerBound..<word.range.upperBound
            } else {
                ranges.append((word.range, value))
            }
        }
        return ranges
    }

    /// Emphasis for the word at the reader's current playback position.
    /// Read on every animation frame; the reader follows the audio clock.
    private func emphasisState(reader: RubyReader, layout: RubyLayout) -> RubyEmphasisState? {
        // Growing words move on every phrase, so Reduce Motion turns it off;
        // color effects and the highlight stay.
        var options = emphasisOptions
        if reduceMotion { options.remove(.grow) }
        guard !options.isEmpty, let word = reader.spokenWord() else { return nil }
        // The reader reads the text as written.
        let placed = layout.place(content.range(fromOriginal: word.range))
        // Ease out over the first moment of the word for grow and highlight.
        let appear = 1 - pow(1 - min(word.elapsed / 0.15, 1), 3)
        return RubyEmphasisState(
            options: options,
            paragraph: placed.paragraph,
            range: placed.range,
            appear: appear,
            progress: word.progress
        )
    }
}

/// Where a `RubyText`'s text was laid out within it.
private struct RubyTextGeometry: Equatable {
    let origin: CGPoint
    let layout: Text.Layout
}

/// A word VoiceOver users can choose as an action.
private struct RubyAccessibilityWord: Identifiable {
    /// Index of the word in the content's dictionary words.
    let id: Int
    let name: Text
}

/// Captures the layout SwiftUI made for the text, and reports taps with
/// it so the tapped word can be found. For VoiceOver, each of `words` is
/// an action that selects it.
private struct RubyWordTapping: ViewModifier {
    let isEnabled: Bool
    let words: [RubyAccessibilityWord]
    let onTap: (CGPoint, RubyTextGeometry) -> Void
    /// Selects the word with an ID of `words`, for VoiceOver.
    let onActivate: (Int, RubyTextGeometry) -> Void

    @State private var geometry: RubyTextGeometry?

    func body(content: Content) -> some View {
        let tappable = content
            .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                if isEnabled {
                    GeometryReader { proxy in
                        let current = layouts.first.map { RubyTextGeometry(origin: proxy[$0.origin], layout: $0.layout) }
                        Color.clear.onChange(of: current, initial: true) { geometry = current }
                    }
                }
            }
            // Simultaneous, so text selection keeps working.
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    if let geometry { onTap(tap.location, geometry) }
                },
                isEnabled: isEnabled
            )
        if isEnabled {
            tappable
                .accessibilityActions {
                    // SwiftUI lists actions last first, so the words are
                    // declared from the end to be listed in text order.
                    ForEach(words.reversed()) { word in
                        Button {
                            if let geometry { onActivate(word.id, geometry) }
                        } label: {
                            word.name
                        }
                    }
                }
                // Double-tapping would otherwise tap the middle of the
                // text, whichever word is there; choose the first instead.
                .accessibilityAction {
                    if let geometry, let word = words.first { onActivate(word.id, geometry) }
                }
                .accessibilityHint(Text(.chooseWordHint))
        } else {
            tappable
        }
    }
}

/// Paragraphs of a `RubyText` that break between characters, because
/// breaking as the text asks started one of their lines with a character
/// that may not start one, and the text and width they were found for.
private struct RubyLineBreakFallback: Equatable {
    /// What the text's lines depend on, besides its width.
    struct Key: Equatable {
        let string: String
        let font: String
        let lineBreaking: RubyLineBreaking
    }

    let key: Key
    /// The width proposed to the text, `nil` for as wide as it likes.
    let width: CGFloat?
    /// The paragraphs, by index.
    let paragraphs: Set<Int>
}

/// Keeps 。 and other characters that may not start a line off the start
/// of a `RubyText`'s lines.
///
/// Breaking between phrases, the system breaks a phrase wider than the
/// line after the last character that fits, even before 。, and nothing
/// in the text can stop it. So once the text is laid out, each paragraph
/// with a line that starts badly is laid out again, breaking between
/// characters, for as long as the text, its font and its width stay the
/// same. Text at ordinary sizes, whose phrases fit on a line, is left as
/// it is.
private struct RubyLineStartCheck: ViewModifier {
    /// Whether the text has a character that may not start a line.
    let isEnabled: Bool
    let key: RubyLineBreakFallback.Key
    @Binding var fallback: RubyLineBreakFallback?

    @State private var proposedWidth = RubyProposedWidth()

    func body(content: Content) -> some View {
        RubyProposedWidthReader(width: proposedWidth) {
            content
        }
        .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
            if isEnabled {
                Color.clear.onChange(of: layouts.first?.layout, initial: true) { _, layout in
                    if let layout { check(layout) }
                }
            }
        }
    }

    /// Finds the paragraphs in `layout` that need to break between
    /// characters, adding to those already found for the same text and
    /// width.
    private func check(_ layout: Text.Layout) {
        let width = proposedWidth.value
        var paragraphs: Set<Int> = []
        if let fallback, fallback.key == key {
            // In another width, the paragraphs may fit between phrases
            // again: they're laid out between phrases and checked again.
            guard fallback.width == width else {
                self.fallback = nil
                return
            }
            paragraphs = fallback.paragraphs
        }
        let lineStarts = layout.rubyParagraphLines.compactMap { _, line, paragraph, start in
            line.flatMap(\.characterIndices).min().map { (paragraph: paragraph, offset: start.distance(to: $0)) }
        }
        let broken = RubyLineBreaking.badlyBrokenParagraphs(in: key.string, lineStarts: lineStarts)
        // Paragraphs already breaking between characters can't do better.
        guard !broken.isSubset(of: paragraphs) else { return }
        fallback = RubyLineBreakFallback(key: key, width: width, paragraphs: paragraphs.union(broken))
    }
}

/// Lays out its view as proposed, and notes the width proposed. Text is as
/// wide as its longest line, so its size alone doesn't show whether it
/// was given another width.
private struct RubyProposedWidthReader: Layout {
    let width: RubyProposedWidth

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        width.value = proposal.width
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }

    // The text's own guides, such as its baselines, pass through.
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        subviews.first?.dimensions(in: proposal)[explicit: guide].map { bounds.minY + $0 }
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        subviews.first?.dimensions(in: proposal)[explicit: guide].map { bounds.minX + $0 }
    }
}

/// The width last proposed to a `RubyText`'s text. A reference, so noting
/// it during layout doesn't update the view, and locked, since layout
/// isn't isolated to the main actor.
private nonisolated final class RubyProposedWidth: Sendable {
    private let storage = Mutex<CGFloat?>(nil)

    var value: CGFloat? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

extension AttributedString {
    /// This text with what VoiceOver says for each of `speech`'s ranges,
    /// as SSML that replaces the range's text in speech only.
    func speaking(_ speech: [RubySpokenText]) -> AttributedString {
        guard !speech.isEmpty else { return self }
        // Built from pieces, since indices don't outlive a mutation. The
        // ranges are in order, so each is found from the one before.
        var text = AttributedString()
        var index = utf16.startIndex
        var offset = 0
        for item in speech where item.range.lowerBound >= offset {
            let lower = utf16.index(index, offsetBy: item.range.lowerBound - offset)
            let upper = utf16.index(lower, offsetBy: item.range.count)
            text.append(self[index..<lower])
            var spoken = AttributedString(self[lower..<upper])
            spoken.accessibilitySpeechSSML = item.ssml
            text.append(spoken)
            index = upper
            offset = item.range.upperBound
        }
        text.append(self[index...])
        return text
    }
}

/// A list of values SwiftUI interpolates element by element, such as how
/// visible each furigana reading is, so each fades or moves on its own.
nonisolated struct RubyAnimatableVector: VectorArithmetic {
    var values: [Double]

    /// The value at `index`, or `fallback` past the end.
    func value(at index: Int, default fallback: CGFloat) -> CGFloat {
        values.indices.contains(index) ? values[index] : fallback
    }

    var isZero: Bool { values.allSatisfy { $0 == 0 } }

    static var zero: Self { Self(values: []) }

    static func + (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, with: +) }
    static func - (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, with: -) }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    /// Combines element-wise, treating missing elements as 0.
    private static func combine(_ lhs: Self, _ rhs: Self, with operation: (Double, Double) -> Double) -> Self {
        let count = max(lhs.values.count, rhs.values.count)
        return Self(values: (0..<count).map { index in
            operation(
                lhs.values.indices.contains(index) ? lhs.values[index] : 0,
                rhs.values.indices.contains(index) ? rhs.values[index] : 0
            )
        })
    }
}

/// Font measurements for one text, computed once and reused for every
/// annotation strength, so animating the style doesn't re-measure text.
final class RubyMeasurements {
    struct Furigana {
        /// Index among all of the content's readings, for its visibility.
        let source: Int
        /// Characters the reading sits over.
        let characters: Range<Int>
        /// UTF-16 range of those characters.
        let range: Range<Int>
        let text: String
        /// How much the reading is narrowed horizontally, from 1 (natural
        /// width) down to `RubyMeasurements.minimumScale`.
        let scale: CGFloat
        /// How much wider the reading, as narrowed, is than its base text.
        let extraWidth: CGFloat
        /// How far the reading may extend over the characters before and
        /// after its base, which have no readings of their own, before the
        /// base needs space around it.
        let leadingOverhang: CGFloat
        let trailingOverhang: CGFloat
        /// Whether the base starts a paragraph. The reading then starts
        /// with it instead of being centered, so the line isn't indented.
        let startsParagraph: Bool
        /// Characters that move together when the reading needs more
        /// space: its word, as far as the reading may overhang, so space
        /// goes around the word (夥しい), never between a kanji and its
        /// kana ending (夥|しい).
        let padded: Range<Int>
        /// Whether those characters end their paragraph. The reading then
        /// ends with them and takes its space before them: space after a
        /// paragraph's last character doesn't widen the text.
        let endsParagraph: Bool
    }

    struct Romaji {
        /// Index among the content's romaji words, or its kana's romaji,
        /// for `romajiVisibility` or `kanaRomajiVisibility`.
        let source: Int
        let characters: Range<Int>
        let range: Range<Int>
        let text: String
        /// How much the romaji are narrowed horizontally.
        let scale: CGFloat
        /// Width as drawn, after narrowing.
        let width: CGFloat
    }

    /// How narrow readings over numbers in digits may become. Their readings
    /// are long for their base (にせんにじゅうろく over 2026), so they're
    /// condensed, as Japanese typesetting does with long ruby, rather than
    /// spreading the text apart.
    static let minimumScale: CGFloat = 0.75

    let characters: [Character]
    /// Width of each character in the base font.
    let widths: [CGFloat]
    /// UTF-16 offset where each character starts, plus the end offset.
    let starts: [Int]
    let furigana: [Furigana]
    let romaji: [Romaji]
    /// Romaji under each kana, if they were measured.
    let kanaRomaji: [Romaji]
    /// Indices of the characters that are spaces put between phrases of
    /// kana text.
    let insertedSpaces: [Int]
    /// UTF-16 offset where each paragraph starts.
    let paragraphStarts: [Int]
    /// The end of each paragraph, kept on one line when lines may break
    /// anywhere; see `RubyLineBreaking.endings(in:)`.
    let endings: [Range<Int>]
    /// The weight of each character set in its own weight.
    let weights: [Font.Weight?]

    /// What measurements depend on. Content objects are cached too, so the
    /// same text read by another analyzer is a different object.
    private struct Key: Hashable {
        let metrics: String
        let furiganaScript: RubyScript
        let romanization: RubyRomanization
        let content: ObjectIdentifier
        let string: String
        let weights: [RubyWeightedRange]
        let kanaRomaji: Bool
    }

    private static let cache = NSCache<RubyCacheKey<Key>, RubyMeasurements>()

    static func measurements(
        for content: RubyContent,
        metrics: RubyMetrics,
        furiganaScript: RubyScript,
        romanization: RubyRomanization,
        weights: [RubyWeightedRange] = [],
        kanaRomaji: Bool = false
    ) -> RubyMeasurements {
        let key = RubyCacheKey(Key(
            metrics: metrics.cacheKey,
            furiganaScript: furiganaScript,
            romanization: romanization,
            content: ObjectIdentifier(content),
            string: content.string,
            weights: weights,
            kanaRomaji: kanaRomaji
        ))
        if let cached = cache.object(forKey: key) { return cached }
        var weighted: [Font.Weight: RubyMetrics] = [:]
        func fontMetrics(_ weight: Font.Weight?) -> RubyMetrics {
            guard let weight else { return metrics }
            if let cached = weighted[weight] { return cached }
            let result = metrics.weighted(weight)
            weighted[weight] = result
            return result
        }
        let measurements = RubyMeasurements(
            content: content,
            furiganaScript: furiganaScript,
            romanization: romanization,
            weights: weights,
            kanaRomaji: kanaRomaji,
            baseWidth: { fontMetrics($1).baseWidth(of: $0) },
            annotationWidth: { fontMetrics($1).annotationWidth(of: $0) }
        )
        cache.setObject(measurements, forKey: key)
        return measurements
    }

    /// Measures `content` with the given text widths in each weight, which
    /// tests can supply without fonts. Text outside `weights` is measured
    /// with no weight, in the font's own.
    ///
    /// - Parameter kanaRomaji: Whether to measure romaji under each kana,
    ///   which most text doesn't show.
    init(
        content: RubyContent,
        furiganaScript: RubyScript = .hiragana,
        romanization: RubyRomanization = .hepburn,
        weights: [RubyWeightedRange] = [],
        kanaRomaji measuresKanaRomaji: Bool = false,
        baseWidth: (String, Font.Weight?) -> CGFloat,
        annotationWidth: (String, Font.Weight?) -> CGFloat
    ) {
        let characters = Array(content.string)
        var starts: [Int] = []
        var offset = 0
        for character in characters {
            starts.append(offset)
            offset += character.utf16.count
        }
        starts.append(offset)

        func characterRange(_ range: Range<Int>) -> Range<Int> {
            Self.index(of: range.lowerBound, in: starts)..<Self.index(of: range.upperBound, in: starts)
        }

        var characterWeights = [Font.Weight?](repeating: nil, count: characters.count)
        for item in weights {
            for index in characterRange(item.range) { characterWeights[index] = item.weight }
        }
        let widths = characters.indices.map { baseWidth(String(characters[$0]), characterWeights[$0]) }
        let readings = content.words.flatMap { word in
            word.furigana.map { reading in
                (reading: (range: reading.range, text: RubyContent.text(of: reading, in: furiganaScript)), word: word.range)
            }
        }
        var hasReading = [Bool](repeating: false, count: characters.count)
        for (reading, _) in readings {
            for index in characterRange(reading.range) { hasReading[index] = true }
        }
        // How far a reading may extend past its base on one side: over
        // every neighboring character without a reading of its own, such as
        // kana, letters, digits, and punctuation, so a long reading flows
        // over them (にせんにじゅうろくねん over 2026年に) instead of pushing
        // them apart. When another reading sits beyond that space, the two
        // share it, with a small gap between them.
        let readingGap = annotationWidth("あ", nil) / 4
        // Also returns where the space it may overhang ends: the index of
        // the first character past it.
        func overhang(from start: Int, step: Int) -> (width: CGFloat, end: Int) {
            var allowance: CGFloat = 0
            var index = start
            while characters.indices.contains(index), !hasReading[index], !characters[index].isNewline {
                allowance += widths[index]
                index += step
            }
            let shared = characters.indices.contains(index) && hasReading[index]
            return (shared ? max(0, allowance / 2 - readingGap / 2) : allowance, index)
        }

        /// How much to narrow an annotation `width` wide over `indices`, so
        /// it fits in `available` where possible: only over numbers in
        /// digits, and no narrower than `minimumScale`.
        func scale(_ width: CGFloat, over indices: Range<Int>, available: CGFloat) -> CGFloat {
            guard width > available, RubyText.isDigitNumber(String(characters[indices])) else { return 1 }
            return max(Self.minimumScale, available / width)
        }

        var furigana: [Furigana] = []
        for (source, (reading, word)) in readings.enumerated() {
            let indices = characterRange(reading.range)
            guard !indices.isEmpty else { continue }
            let baseWidth = indices.reduce(0) { $0 + widths[$1] }
            let (leading, leadingEnd) = overhang(from: indices.lowerBound - 1, step: -1)
            let (trailing, trailingEnd) = overhang(from: indices.upperBound, step: 1)
            let wordIndices = characterRange(word)
            let padded = max(wordIndices.lowerBound, leadingEnd + 1)..<min(wordIndices.upperBound, trailingEnd)
            let natural = annotationWidth(reading.text, characterWeights[indices.lowerBound])
            let scale = scale(natural, over: indices, available: baseWidth + leading + trailing)
            furigana.append(Furigana(
                source: source,
                characters: indices,
                range: reading.range,
                text: reading.text,
                scale: scale,
                extraWidth: natural * scale - baseWidth,
                leadingOverhang: leading,
                trailingOverhang: trailing,
                startsParagraph: indices.lowerBound == 0 || characters[indices.lowerBound - 1].isNewline,
                padded: padded,
                endsParagraph: padded.upperBound == characters.count || characters[padded.upperBound].isNewline
            ))
        }
        /// Romaji under `range`, narrowed like readings over numbers.
        func measuredRomaji(_ text: String, over range: Range<Int>, source: Int) -> Romaji? {
            let indices = characterRange(range)
            guard !indices.isEmpty else { return nil }
            let natural = annotationWidth(text, characterWeights[indices.lowerBound])
            let scale = scale(natural, over: indices, available: indices.reduce(0) { $0 + widths[$1] })
            return Romaji(source: source, characters: indices, range: range, text: text, scale: scale, width: natural * scale)
        }
        let romaji = content.romajiWords(in: romanization).enumerated().compactMap { source, word in
            measuredRomaji(word.text, over: word.range, source: source)
        }
        let kanaRomaji = !measuresKanaRomaji ? [] : content.kanaRomaji(in: romanization).enumerated().compactMap { source, beat in
            measuredRomaji(beat.text, over: beat.range, source: source)
        }

        self.characters = characters
        self.widths = widths
        self.starts = starts
        self.furigana = furigana
        self.romaji = romaji
        self.kanaRomaji = kanaRomaji
        insertedSpaces = content.spaces.map { Self.index(of: $0, in: starts) }
        paragraphStarts = RubyLineBreaking.paragraphRanges(in: content.string).map(\.lowerBound)
        endings = RubyLineBreaking.endings(in: content)
        self.weights = characterWeights
    }

    /// Index of the character starting at a UTF-16 offset (binary search).
    static func index(of offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] < offset { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// The attributed text and renderer data for one set of annotation strengths.
struct RubyLayout {
    let text: AttributedString
    let paragraphs: [RubyParagraph]
    private let paragraphStarts: [Int]

    init(
        measurements: RubyMeasurements,
        furigana: CGFloat,
        romaji: CGFloat,
        readingVisibility: RubyAnimatableVector,
        romajiVisibility: RubyAnimatableVector,
        kanaRomaji: CGFloat = 0,
        kanaRomajiVisibility: RubyAnimatableVector = .zero,
        wordGaps: RubyAnimatableVector,
        fontSize: CGFloat,
        romajiSpacing: CGFloat,
        lineBreaking: RubyLineBreaking,
        characterBreaking: Set<Int> = [],
        insertedSpaceWidth: CGFloat,
        textColors: [RubyColoredRange],
        backgrounds: [RubyColoredRange],
        weightedMetrics: [Font.Weight: RubyMetrics] = [:]
    ) {
        let characters = measurements.characters
        let starts = measurements.starts
        // Words in their own weight are set in their own font, as their
        // characters were measured, and so are their annotations.
        let weights = measurements.weights

        // Word colors per character. They're applied as the standard
        // foreground color attribute, which copies safely.
        var colors = [Color?](repeating: nil, count: characters.count)
        for item in textColors {
            let lower = RubyMeasurements.index(of: item.range.lowerBound, in: starts)
            let upper = RubyMeasurements.index(of: item.range.upperBound, in: starts)
            for index in lower..<upper { colors[index] = item.color }
        }

        // The renderer can't change layout, so annotations get room through
        // tracking: space after a character. Glyphs then shift right within
        // that space, so a word's kanji stay together with the space around
        // the word, never between its characters.
        let spacing = Self.spacing(
            measurements: measurements,
            furigana: furigana,
            romaji: romaji,
            readingVisibility: readingVisibility,
            romajiVisibility: romajiVisibility,
            kanaRomaji: kanaRomaji,
            kanaRomajiVisibility: kanaRomajiVisibility,
            wordGaps: wordGaps,
            fontSize: fontSize,
            romajiSpacing: romajiSpacing,
            insertedSpaceWidth: insertedSpaceWidth
        )
        let tracking = spacing.tracking
        let shifts = spacing.shifts

        // Build one flat attributed string with a run per tracking value,
        // color and weight.
        var text = AttributedString()
        var tracked: [RubyTrackedRange] = []
        var lower = 0
        while lower < characters.count {
            var upper = lower + 1
            while upper < characters.count, tracking[upper] == tracking[lower], shifts[upper] == shifts[lower],
                  colors[upper] == colors[lower], weights[upper] == weights[lower] {
                upper += 1
            }
            var piece = AttributedString(String(characters[lower..<upper]))
            piece.foregroundColor = colors[lower]
            piece.font = weights[lower].flatMap { weightedMetrics[$0]?.textFont }
            if tracking[lower] > 0 || shifts[lower] > 0 {
                piece.tracking = tracking[lower]
                tracked.append(RubyTrackedRange(range: starts[lower]..<starts[upper], tracking: tracking[lower], shift: shifts[lower]))
            }
            text.append(piece)
            lower = upper
        }
        // The language decides where lines may break, such as only between
        // phrases. It's a standard attribute, so copying still works.
        lineBreaking.setLanguage(of: &text, endings: measurements.endings, characterBreaking: characterBreaking)
        self.text = text

        // Layout character indices restart at each paragraph, so ranges are
        // converted to paragraph-relative offsets.
        let paragraphStarts = measurements.paragraphStarts
        self.paragraphStarts = paragraphStarts
        var paragraphs = [RubyParagraph](repeating: RubyParagraph(), count: paragraphStarts.count)
        for item in tracked {
            let placed = Self.place(item.range, paragraphStarts: paragraphStarts)
            paragraphs[placed.paragraph].tracked.append(RubyTrackedRange(range: placed.range, tracking: item.tracking, shift: item.shift))
        }
        if furigana > 0 {
            for (id, reading) in measurements.furigana.enumerated() {
                let visibility = readingVisibility.value(at: reading.source, default: 1)
                guard visibility > 0 else { continue }
                let placed = Self.place(reading.range, paragraphStarts: paragraphStarts)
                paragraphs[placed.paragraph].furigana.append(RubyAnnotation(
                    id: id, text: reading.text, range: placed.range, baseCount: reading.characters.count,
                    color: colors[reading.characters.lowerBound],
                    font: weights[reading.characters.lowerBound].flatMap { weightedMetrics[$0]?.annotationFont },
                    opacity: visibility,
                    scale: reading.scale
                ))
            }
        }
        // Romaji and kana romaji, each where their strength shows them.
        func annotations(_ romaji: [RubyMeasurements.Romaji], visibility: RubyAnimatableVector) -> [(paragraph: Int, annotation: RubyAnnotation)] {
            romaji.enumerated().compactMap { id, word in
                let opacity = visibility.value(at: word.source, default: 1)
                guard opacity > 0 else { return nil }
                let placed = Self.place(word.range, paragraphStarts: paragraphStarts)
                return (placed.paragraph, RubyAnnotation(
                    id: id, text: word.text, range: placed.range, baseCount: word.characters.count,
                    color: colors[word.characters.lowerBound],
                    font: weights[word.characters.lowerBound].flatMap { weightedMetrics[$0]?.annotationFont },
                    opacity: opacity,
                    scale: word.scale
                ))
            }
        }
        if romaji > 0 {
            for (paragraph, annotation) in annotations(measurements.romaji, visibility: romajiVisibility) {
                paragraphs[paragraph].romaji.append(annotation)
            }
        }
        if kanaRomaji > 0 {
            for (paragraph, annotation) in annotations(measurements.kanaRomaji, visibility: kanaRomajiVisibility) {
                paragraphs[paragraph].kanaRomaji.append(annotation)
            }
        }
        for item in backgrounds {
            let placed = Self.place(item.range, paragraphStarts: paragraphStarts)
            paragraphs[placed.paragraph].backgrounds.append(RubyColoredRange(range: placed.range, color: item.color))
        }
        self.paragraphs = paragraphs
    }

    /// Space after each character, and how far right each glyph moves
    /// within the space before it, to fit annotations and word spacing.
    static func spacing(
        measurements: RubyMeasurements,
        furigana: CGFloat,
        romaji: CGFloat,
        readingVisibility: RubyAnimatableVector,
        romajiVisibility: RubyAnimatableVector,
        kanaRomaji: CGFloat = 0,
        kanaRomajiVisibility: RubyAnimatableVector = .zero,
        wordGaps: RubyAnimatableVector,
        fontSize: CGFloat,
        romajiSpacing: CGFloat,
        insertedSpaceWidth: CGFloat = 0
    ) -> (tracking: [CGFloat], shifts: [CGFloat]) {
        let characters = measurements.characters
        let widths = measurements.widths
        var tracking = [CGFloat](repeating: 0, count: characters.count)
        var shifts = [CGFloat](repeating: 0, count: characters.count)

        // Adds space before and after a run of characters. Space before it
        // goes after the character before it; at the start of a paragraph,
        // the run's glyphs move right instead.
        func pad(_ indices: Range<Int>, before: CGFloat, after: CGFloat) {
            let previous = indices.lowerBound - 1
            if previous >= 0, !characters[previous].isNewline {
                tracking[previous] += before
            } else {
                for index in indices { shifts[index] += before }
                tracking[indices.upperBound - 1] += before
            }
            tracking[indices.upperBound - 1] += after
        }

        // Furigana wider than their base, beyond what neighboring kana can
        // take, get space on either side of the base, scaled by how strongly
        // they show.
        if furigana > 0 {
            for reading in measurements.furigana where reading.extraWidth > 0 {
                let excess = reading.extraWidth * furigana * readingVisibility.value(at: reading.source, default: 1)
                if reading.startsParagraph {
                    pad(reading.padded, before: 0, after: max(0, excess - reading.trailingOverhang))
                } else if reading.endsParagraph {
                    pad(reading.padded, before: max(0, excess - reading.trailingOverhang - reading.leadingOverhang), after: 0)
                } else {
                    pad(
                        reading.padded,
                        before: max(0, excess / 2 - reading.leadingOverhang),
                        after: max(0, excess / 2 - reading.trailingOverhang)
                    )
                }
            }
        }

        // Word spacing pads after the last character of a word.
        for index in characters.indices {
            tracking[index] += wordGaps.value(at: measurements.starts[index + 1], default: 0) * fontSize
        }
        // Spaces put between phrases of kana text take the spacing's width.
        for index in measurements.insertedSpaces {
            tracking[index] += insertedSpaceWidth * fontSize - widths[index]
        }

        // Romaji are centered under their words and may extend past them,
        // so only neighbors that would collide are moved apart. Positions
        // are measured within each paragraph as if it were one line.
        var paragraphOf = [Int](repeating: 0, count: characters.count)
        var paragraphEnds: [Int] = []
        for (index, character) in characters.enumerated() {
            paragraphOf[index] = paragraphEnds.count
            if character.isNewline { paragraphEnds.append(index) }
        }
        paragraphEnds.append(characters.count)

        func separate(_ annotations: [RubyMeasurements.Romaji], strength: CGFloat, visibilities: RubyAnimatableVector, spacing: CGFloat) {
            guard strength > 0, !annotations.isEmpty else { return }
            var x = [CGFloat](repeating: 0, count: characters.count + 1)
            for index in characters.indices {
                x[index + 1] = characters[index].isNewline ? 0 : x[index] + widths[index] + tracking[index]
            }

            var paragraph = -1
            var added: CGFloat = 0
            var previousRight: CGFloat?

            for word in annotations {
                let visibility = strength * visibilities.value(at: word.source, default: 1)
                guard visibility > 0 else { continue }
                let first = word.characters.lowerBound
                let last = word.characters.upperBound - 1
                if paragraphOf[first] != paragraph {
                    paragraph = paragraphOf[first]
                    added = 0
                    previousRight = nil
                }

                let left = x[first] + shifts[first] + added
                let right = x[last] + shifts[last] + widths[last] + added
                var center = (left + right) / 2
                let half = word.width / 2
                // Romaji that would run past the paragraph's end end with it,
                // since space after its last character doesn't widen the text,
                // and those that would start before it start with it.
                let end = x[paragraphEnds[paragraph]] + added
                center = max(min(center, end - half), half)
                if let previousRight {
                    let overlap = previousRight + spacing - (center - half)
                    if overlap > 0 {
                        tracking[first - 1] += overlap * visibility
                        added += overlap * visibility
                        center += overlap * visibility
                    }
                }
                previousRight = center + half
            }
        }
        separate(measurements.romaji, strength: romaji, visibilities: romajiVisibility, spacing: romajiSpacing)
        // Kana romaji are beats, closer together than words are.
        separate(measurements.kanaRomaji, strength: kanaRomaji, visibilities: kanaRomajiVisibility, spacing: romajiSpacing / 2)
        return (tracking, shifts)
    }

    /// Converts a paragraph-relative UTF-16 offset to one in the whole text.
    func offset(_ offset: Int, inParagraph paragraph: Int) -> Int {
        (paragraphStarts.indices.contains(paragraph) ? paragraphStarts[paragraph] : 0) + offset
    }

    /// Converts a UTF-16 range in the whole text to its paragraph and a
    /// paragraph-relative range.
    func place(_ range: Range<Int>) -> (paragraph: Int, range: Range<Int>) {
        Self.place(range, paragraphStarts: paragraphStarts)
    }

    private static func place(_ range: Range<Int>, paragraphStarts: [Int]) -> (paragraph: Int, range: Range<Int>) {
        let paragraph = (paragraphStarts.lastIndex { $0 <= range.lowerBound }) ?? 0
        let start = paragraphStarts[paragraph]
        return (paragraph, (range.lowerBound - start)..<(range.upperBound - start))
    }
}

// RubyUI doesn't include a dictionary, so previews read from markup.

#Preview("Ruby styles") {
    let sentence = "{吾輩|わがはい}は{猫|ねこ}である。{名前|なまえ}はまだ{無|な}い。{日本語|にほんご}を{勉強|べんきょう}しています。"

    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            RubyText(markup: sentence)
                .rubyStyle()

            RubyText(markup: sentence)
                .rubyStyle(.romaji)

            RubyText(markup: sentence)
                .rubyStyle([.furigana, .romaji])

            RubyText(markup: sentence)
                .rubyStyle([])

            // Multiple paragraphs.
            RubyText("{今日|きょう}は{東京|とうきょう}へ{行|い}きたい。\n\nコーヒーを{飲|の}みたい。")
                .font(.title2.bold())
                .rubyStyle([.furigana, .romaji])

            // Long word forced to wrap: its reading is split, not duplicated.
            RubyText("きのう{日本語能力試験|にほんごのうりょくしけん}を{受|う}けた。")
                .frame(width: 160, alignment: .leading)
                .rubyStyle()
        }
        .textSelection(.enabled)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Largest text size") {
    // Each sentence has a phrase wider than the line, which would leave 。
    // alone at the start of the next, so it breaks between characters.
    VStack(alignment: .leading, spacing: 28) {
        RubyText("アリョーナです。よろしく{お願|ねが}いします。")
        RubyText("{森|もり}さん、よろしく{お願|ねが}いします。")
        // Phrases that fit still break between phrases.
        RubyText("{今日|きょう}は{東京|とうきょう}へ{行|い}きたい。")
    }
    .font(.title)
    // The width of text on a 375-point iPhone.
    .frame(width: 343, alignment: .leading)
    .dynamicTypeSize(.accessibility5)
}

#Preview("Colors") {
    let sentence = "{吾輩|わがはい}は{猫|ねこ}である。{名前|なまえ}はまだ{無|な}い。"

    VStack(alignment: .leading, spacing: 28) {
        // Default: furigana in secondary, romaji in tertiary.
        RubyText(markup: sentence)

        // Furigana and romaji colored separately from the text.
        RubyText(markup: sentence)
            .foregroundStyle(.primary, .red, .blue)

        // A single style tints everything; the levels derive from it.
        RubyText(markup: sentence)
            .foregroundStyle(.indigo)

        // Everything in the text color, like printed books.
        RubyText(markup: sentence)
            .foregroundStyle(.primary, .primary, .primary)
    }
    .font(.title3)
    .rubyStyle([.furigana, .romaji])
    .padding()
}

#Preview("Romaji under kana") {
    @Previewable @State var known: Set<String> = []
    let kana = ["わ", "た", "し", "は", "で", "す", "コ", "ー", "ヒ"]

    VStack(alignment: .leading, spacing: 24) {
        // Segments say は and を are particles, which markup alone can't.
        RubyText(segments: [
            RubySegment("わたし"), RubySegment("は", word: .init(partOfSpeech: .particle)),
            RubySegment("学生", reading: "がくせい"), RubySegment("です"), RubySegment("。", source: .dictionary),
            RubySegment("コーヒー"), RubySegment("を", word: .init(partOfSpeech: .particle)),
            RubySegment("ください"), RubySegment("。", source: .dictionary),
        ])
            .font(.title2)
            .rubyStyle([.furigana, .kanaRomaji])
            .rubyKanaRomaji(.except(known))
            .foregroundStyle(.primary, .secondary, .tint)

        ForEach(kana, id: \.self) { kana in
            Toggle(isOn: Binding(
                get: { known.contains(kana) },
                set: { if $0 { known.insert(kana) } else { known.remove(kana) } }
            )) {
                Text(verbatim: "\(kana) learned")
            }
        }
    }
    .padding()
}

#Preview("Animated style") {
    @Previewable @State var style: RubyStyle = .furigana

    VStack(alignment: .leading, spacing: 24) {
        RubyText("{吾輩|わがはい}は{猫|ねこ}である。{名前|なまえ}はまだ{無|な}い。")
            .font(.title2)
            .rubyStyle(style)

        Picker("Style", selection: $style) {
            Text("None").tag(RubyStyle())
            Text("Furigana").tag(RubyStyle.furigana)
            Text("Romaji").tag(RubyStyle.romaji)
            Text("Both").tag(RubyStyle([.furigana, .romaji]))
        }
        .pickerStyle(.segmented)
    }
    .padding()
}
