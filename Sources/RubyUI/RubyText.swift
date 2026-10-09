import Accessibility
import RubyCore
import RubyTransliteration
import SwiftUI

/// Japanese text that can show furigana or romaji above its words, or
/// furigana above and romaji below.
///
/// Use it like `Text`, and choose annotations with `rubyStyle(_:)` on it or
/// any parent view. Readings are generated on device; supply your own with
/// `{base|reading}` markup where the automatic one is wrong:
///
///     RubyText("{今日|きょう}は日本語を勉強しています。")
///         .font(.title)
///         .textSelection(.enabled)
///         .rubyStyle([.furigana, .romaji])
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
/// Changing the style animates: annotations fade in or out, and the line
/// spacing and letter spacing they need ease to their new values. Text
/// rewritten in another script rolls into the new text glyph by glyph,
/// like `numericText()`.
///
/// Furigana use the secondary foreground style and romaji the tertiary one,
/// so they're quieter than the text by default and can be colored with the
/// standard modifiers:
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
/// a `RubyMeCabAnalyzer` with the IPAdic dictionary your app bundles;
/// without one, only readings in `{base|reading}` markup show. Add
/// `rubyModelReadings()` to have Apple's on-device model read words whose
/// reading depends on their meaning.
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
        case markup(String)
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
    @Environment(\.rubyDigitReadingsHidden) private var digitReadingsHidden
    @Environment(\.rubySpacing) private var spacing
    @Environment(\.rubyWordColoring) private var wordColoring
    @Environment(\.rubyDictionary) private var dictionary
    @Environment(\.rubyModelReadings) private var modelUpdates
    @Environment(\.rubySpokenReadings) private var spokenReadings
    @Environment(\.rubyShowsWordDetails) private var showsWordDetails
    @Environment(\.rubyWordTapAction) private var wordTapAction
    /// Content with the model's readings, once it has answered, and the
    /// input it's for.
    @State private var modelContent: (key: ModelKey, content: RubyContent)?
    /// The tapped word whose details are showing, and where it is.
    @State private var selectedWord: RubyWordInfo?
    @State private var selectedRect = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates ruby text from a localized string, like `Text("…")`.
    public init(_ resource: LocalizedStringResource) {
        input = .markup(String(localized: resource))
    }

    /// Creates ruby text from a string without localizing it.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        input = .markup(String(content))
    }

    /// Creates ruby text from a string without localizing it.
    public init(verbatim content: String) {
        input = .markup(content)
    }

    /// Creates ruby text from segments you supply, such as readings from
    /// your own data store, with no on-device analysis.
    public init(segments: [RubySegment]) {
        input = .segments(segments)
    }

    public var body: some View {
        // Cached per markup or segment array, so this is cheap after the
        // first time. The dictionary's readings show until the model's
        // arrive.
        let analyzed: RubyContent = if let modelContent, modelContent.key == modelKey {
            modelContent.content
        } else {
            switch input {
            case .markup(let markup): .content(for: markup, analyzer: analyzer)
            case .segments(let segments): .content(for: segments)
            }
        }
        let content = rewritten(analyzed)
        let speech = content.speech(spokenReadings)
        let placement = RubyPlacement(style: style, furiganaPosition: furiganaPosition, transcription: transcription)
        RubyTextContent(
            content: content,
            furigana: placement.furigana ? 1 : 0,
            romajiAbove: placement.romajiAbove ? 1 : 0,
            romajiBelow: placement.romajiBelow ? 1 : 0,
            readingVisibility: readingVisibility(in: content),
            romajiVisibility: romajiVisibility(in: content),
            wordGaps: wordGaps(in: content),
            // Computed here, not inside the animated content view, so
            // style transitions don't re-run vocabulary and JLPT lookups
            // on every frame.
            textColors: RubyTextContent.coloredRanges(wordColoring.text, in: content),
            backgroundColors: RubyTextContent.coloredRanges(wordColoring.background, in: content),
            speech: speech,
            accessibilityWords: showsWordDetails || wordTapAction != nil
                ? RubyTextContent.accessibilityWords(in: content, speech: speech)
                : [],
            // Word details describe the word as written.
            selectedRange: selectedWord.map { content.range(fromOriginal: $0.range) },
            selectedWord: $selectedWord,
            selectedRect: $selectedRect
        )
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: digitReadingsHidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: spacing)
        .task(id: modelKey) {
            await loadModelReadings()
        }
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

    /// What the model's readings depend on: the markup, the analyzer, and
    /// whether they're on and how they update.
    private struct ModelKey: Equatable {
        let markup: String?
        let analyzer: AnyHashable?
        let updates: RubyModelReadingUpdates?
    }

    private var modelKey: ModelKey {
        let markup: String? = if case .markup(let markup) = input { markup } else { nil }
        return ModelKey(markup: markup, analyzer: analyzer.map { AnyHashable($0) }, updates: modelUpdates)
    }

    /// Asks the model about words whose reading depends on their meaning,
    /// and shows its readings as the updates option says. Segments you
    /// supply are shown as they are.
    private func loadModelReadings() async {
        let key = modelKey
        guard let updates = key.updates, let markup = key.markup, analyzer != nil, RubyModelReadings.isAvailable else { return }
        #if canImport(FoundationModels)
        let onEachReading: ((RubyContent) async -> Void)? = if updates == .asAnswered {
            { content in
                guard !Task.isCancelled else { return }
                modelContent = (key, content)
            }
        } else {
            nil
        }
        let content = await RubyContent.content(
            for: markup,
            analyzer: analyzer,
            chooser: RubyFoundationModelsChooser(),
            onEachReading: onEachReading
        )
        guard !Task.isCancelled else { return }
        modelContent = (key, content)
        #endif
    }

    /// Whether the filter shows each furigana reading, in content order.
    /// Always one value per reading, even when all show, so animating
    /// between filters interpolates each reading from its old visibility.
    private func readingVisibility(in content: RubyContent) -> RubyAnimatableVector {
        RubyAnimatableVector(values: content.words.flatMap(\.furigana).map { reading in
            let base = RubyReadingUnits.substring(of: content.string, utf16Range: reading.range)
            if digitReadingsHidden && Self.isDigitNumber(base) { return 0 }
            return furiganaFilter.showsReading(over: base) ? 1 : 0
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
}

/// When `RubyText` shows the readings Apple's on-device model chooses.
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
    /// words and readings. Set it once, near the root of your app, with a
    /// dictionary your app bundles:
    ///
    ///     let analyzer = RubyMeCabAnalyzer(
    ///         dictionary: Bundle.main.url(forResource: "ipadic", withExtension: "bundle")!
    ///     )
    ///
    ///     ContentView()
    ///         .rubyAnalyzer(analyzer)
    ///
    /// Without an analyzer, only readings in `{base|reading}` markup show.
    /// Give a `RubyReader` reading the same text the same analyzer, so the
    /// phrases it emphasizes match the views' words.
    public func rubyAnalyzer(_ analyzer: some RubyAnalyzer) -> some View {
        environment(\.rubyAnalyzer, analyzer)
    }

    /// Has Apple's on-device model read words whose reading depends on
    /// their meaning in `RubyText` views in this hierarchy: 辛い is からい
    /// for spicy food and つらい for a hard parting, 人気 is にんき for
    /// popularity and ひとけ for people around.
    ///
    /// The dictionary reads such words the same way in every sentence.
    /// With this on, text first shows the dictionary's readings, then
    /// updates the ones the model judges are meant differently, usually
    /// within a second. Only words on a built-in list are asked about, and
    /// the model only chooses among that list's readings. Where Apple
    /// Intelligence isn't available, the dictionary's readings stay.
    ///
    /// The model answers about one word at a time, in well under a second
    /// each, so a long text with many such words takes several seconds.
    /// Pass `.asAnswered` to `updates` to change each reading as soon as
    /// its answer comes rather than all together at the end.
    ///
    /// Readings you supply with `{base|reading}` markup or as segments are
    /// never changed.
    public func rubyModelReadings(_ isEnabled: Bool = true, updates: RubyModelReadingUpdates = .allAtOnce) -> some View {
        environment(\.rubyModelReadings, isEnabled ? updates : nil)
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
    var readingVisibility: RubyAnimatableVector
    var romajiVisibility: RubyAnimatableVector
    var wordGaps: RubyAnimatableVector
    /// Precomputed by `RubyText`, so word coloring doesn't re-run its
    /// lookups on every frame of a style animation.
    @AnimatableIgnored let textColors: [RubyColoredRange]
    @AnimatableIgnored let backgroundColors: [RubyColoredRange]
    /// What VoiceOver says in place of parts of the text.
    @AnimatableIgnored let speech: [RubySpokenText]
    /// The words VoiceOver users can choose, if words can be tapped.
    @AnimatableIgnored let accessibilityWords: [RubyAccessibilityWord]

    @AnimatableIgnored @Environment(\.rubyReader) private var reader
    @AnimatableIgnored @Environment(\.rubyEmphasis) private var emphasisOptions
    @AnimatableIgnored @Environment(\.rubyLineBreaking) private var lineBreaking
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

    private var isTappable: Bool { showsWordDetails || wordTapAction != nil }

    /// How strongly romaji show, wherever they are.
    private var romaji: CGFloat { min(1, romajiAbove + romajiBelow) }

    /// How much of the reserved height annotations take above and below
    /// each line.
    private var above: CGFloat { min(1, furigana + romajiAbove) }
    private var below: CGFloat { romajiBelow }

    var body: some View {
        if above == 0 && below == 0 && reader == nil && textColors.isEmpty && backgroundColors.isEmpty
            && wordGaps.isZero && content.spaces.isEmpty && !isTappable {
            Text(Self.plainText(content.string, language: lineBreaking.languageIdentifier).speaking(speech))
                .font(RubyMetrics(font: font ?? .body, in: fontResolutionContext).textFont)
                .contentTransition(.numericText())
        } else {
            let metrics = RubyMetrics(font: font ?? .body, in: fontResolutionContext)
            let layout = RubyLayout(
                measurements: .measurements(
                    for: content,
                    metrics: metrics,
                    furiganaScript: furiganaScript.resolved(romanization),
                    romanization: romanization
                ),
                furigana: furigana,
                romaji: romaji,
                readingVisibility: readingVisibility,
                romajiVisibility: romajiVisibility,
                wordGaps: wordGaps,
                fontSize: metrics.fontSize,
                romajiSpacing: metrics.romajiSpacing,
                language: lineBreaking.languageIdentifier,
                insertedSpaceWidth: spacing.width,
                textColors: textColors,
                backgrounds: backgrounds()
            )

            if let reader {
                // Only tick while this text is the one being read.
                let isReadingThis = reader.text == content.sourceString && reader.isSpeaking
                TimelineView(.animation(paused: !isReadingThis || reader.isPaused)) { _ in
                    annotatedText(layout, metrics: metrics, emphasis: isReadingThis
                        ? emphasisState(reader: reader, layout: layout)
                        : nil)
                }
            } else {
                annotatedText(layout, metrics: metrics, emphasis: nil)
            }
        }
    }

    private func annotatedText(_ layout: RubyLayout, metrics: RubyMetrics, emphasis: RubyEmphasisState?) -> some View {
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
                emphasis: emphasis
            ))
            // Over a material, such as a popover's glass, foreground styles
            // turn vibrant, and text the renderer draws in them, such as
            // annotations, doesn't show. The text keeps the regular styles.
            .environment(\.backgroundMaterial, nil)
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
    private static func plainText(_ string: String, language: String) -> AttributedString {
        var text = AttributedString(string)
        text.languageIdentifier = language
        return text
    }

    /// The ranges `colors` colors, with neighboring words of the same color
    /// merged so a compound like 日本|語 gets one background.
    fileprivate static func coloredRanges(_ colors: RubyWordColors?, in content: RubyContent) -> [RubyColoredRange] {
        guard let colors else { return [] }
        var ranges: [RubyColoredRange] = []
        // Words are colored as written, then wherever rewriting moved them.
        let source = content.original ?? content
        for (word, color) in zip(content.words, colors.colors(for: source.words, in: source.string)) {
            guard let color else { continue }
            if let last = ranges.last, last.color == color, last.range.upperBound == word.range.lowerBound {
                ranges[ranges.count - 1] = RubyColoredRange(range: last.range.lowerBound..<word.range.upperBound, color: color)
            } else {
                ranges.append(RubyColoredRange(range: word.range, color: color))
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
                .accessibilityHint("Swipe up or down to choose a word, then double-tap.")
        } else {
            tappable
        }
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
        /// Index among the content's romaji words, for `romajiVisibility`.
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
    /// Indices of the characters that are spaces put between phrases of
    /// kana text.
    let insertedSpaces: [Int]
    /// UTF-16 offset where each paragraph starts.
    let paragraphStarts: [Int]

    private static let cache = NSCache<NSString, RubyMeasurements>()

    static func measurements(
        for content: RubyContent,
        metrics: RubyMetrics,
        furiganaScript: RubyScript,
        romanization: RubyRomanization
    ) -> RubyMeasurements {
        // Content objects are cached too, so the same text read by another
        // analyzer is a different object.
        let key = "\(metrics.cacheKey) \(furiganaScript) \(romanization) \(ObjectIdentifier(content).hashValue)\n\(content.string)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let measurements = RubyMeasurements(
            content: content,
            furiganaScript: furiganaScript,
            romanization: romanization,
            baseWidth: metrics.baseWidth(of:),
            annotationWidth: metrics.annotationWidth(of:)
        )
        cache.setObject(measurements, forKey: key)
        return measurements
    }

    /// Measures `content` with the given text widths, which tests can
    /// supply without fonts.
    init(
        content: RubyContent,
        furiganaScript: RubyScript = .hiragana,
        romanization: RubyRomanization = .hepburn,
        baseWidth: (String) -> CGFloat,
        annotationWidth: (String) -> CGFloat
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

        let widths = characters.map { baseWidth(String($0)) }
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
        let readingGap = annotationWidth("あ") / 4
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
            let natural = annotationWidth(reading.text)
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
        var romaji: [Romaji] = []
        for (source, word) in content.romajiWords(in: romanization).enumerated() {
            let indices = characterRange(word.range)
            guard !indices.isEmpty else { continue }
            let natural = annotationWidth(word.text)
            let scale = scale(natural, over: indices, available: indices.reduce(0) { $0 + widths[$1] })
            romaji.append(Romaji(
                source: source,
                characters: indices,
                range: word.range,
                text: word.text,
                scale: scale,
                width: natural * scale
            ))
        }

        var paragraphStarts = [0]
        for (index, character) in characters.enumerated() where character.isNewline && character != "\u{2028}" {
            paragraphStarts.append(starts[index + 1])
        }

        self.characters = characters
        self.widths = widths
        self.starts = starts
        self.furigana = furigana
        self.romaji = romaji
        insertedSpaces = content.spaces.map { Self.index(of: $0, in: starts) }
        self.paragraphStarts = paragraphStarts
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
        wordGaps: RubyAnimatableVector,
        fontSize: CGFloat,
        romajiSpacing: CGFloat,
        language: String,
        insertedSpaceWidth: CGFloat,
        textColors: [RubyColoredRange],
        backgrounds: [RubyColoredRange]
    ) {
        let characters = measurements.characters
        let starts = measurements.starts

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
            wordGaps: wordGaps,
            fontSize: fontSize,
            romajiSpacing: romajiSpacing,
            insertedSpaceWidth: insertedSpaceWidth
        )
        let tracking = spacing.tracking
        let shifts = spacing.shifts

        // Build one flat attributed string with a run per tracking value and color.
        var text = AttributedString()
        var tracked: [RubyTrackedRange] = []
        var lower = 0
        while lower < characters.count {
            var upper = lower + 1
            while upper < characters.count, tracking[upper] == tracking[lower], shifts[upper] == shifts[lower],
                  colors[upper] == colors[lower] {
                upper += 1
            }
            var piece = AttributedString(String(characters[lower..<upper]))
            piece.foregroundColor = colors[lower]
            if tracking[lower] > 0 || shifts[lower] > 0 {
                piece.tracking = tracking[lower]
                tracked.append(RubyTrackedRange(range: starts[lower]..<starts[upper], tracking: tracking[lower], shift: shifts[lower]))
            }
            text.append(piece)
            lower = upper
        }
        // The language decides where lines may break, such as only between
        // phrases. It's a standard attribute, so copying still works.
        text.languageIdentifier = language
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
                    opacity: visibility,
                    scale: reading.scale
                ))
            }
        }
        if romaji > 0 {
            for (id, word) in measurements.romaji.enumerated() {
                let visibility = romajiVisibility.value(at: word.source, default: 1)
                guard visibility > 0 else { continue }
                let placed = Self.place(word.range, paragraphStarts: paragraphStarts)
                paragraphs[placed.paragraph].romaji.append(RubyAnnotation(
                    id: id, text: word.text, range: placed.range, baseCount: word.characters.count,
                    color: colors[word.characters.lowerBound],
                    opacity: visibility,
                    scale: word.scale
                ))
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

        guard romaji > 0, !measurements.romaji.isEmpty else { return (tracking, shifts) }

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

        var x = [CGFloat](repeating: 0, count: characters.count + 1)
        for index in characters.indices {
            x[index + 1] = characters[index].isNewline ? 0 : x[index] + widths[index] + tracking[index]
        }

        var paragraph = -1
        var added: CGFloat = 0
        var previousRight: CGFloat?

        for word in measurements.romaji {
            let visibility = romaji * romajiVisibility.value(at: word.source, default: 1)
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
                let overlap = previousRight + romajiSpacing - (center - half)
                if overlap > 0 {
                    tracking[first - 1] += overlap * visibility
                    added += overlap * visibility
                    center += overlap * visibility
                }
            }
            previousRight = center + half
        }
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
            RubyText(verbatim: sentence)
                .rubyStyle()

            RubyText(verbatim: sentence)
                .rubyStyle(.romaji)

            RubyText(verbatim: sentence)
                .rubyStyle([.furigana, .romaji])

            RubyText(verbatim: sentence)
                .rubyStyle([])

            // Multiple paragraphs.
            RubyText(verbatim: "{今日|きょう}は{東京|とうきょう}へ{行|い}きたい。\n\nコーヒーを{飲|の}みたい。")
                .font(.title2.bold())
                .rubyStyle([.furigana, .romaji])

            // Long word forced to wrap: its reading is split, not duplicated.
            RubyText(verbatim: "きのう{日本語能力試験|にほんごのうりょくしけん}を{受|う}けた。")
                .frame(width: 160, alignment: .leading)
                .rubyStyle()
        }
        .textSelection(.enabled)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Colors") {
    let sentence = "{吾輩|わがはい}は{猫|ねこ}である。{名前|なまえ}はまだ{無|な}い。"

    VStack(alignment: .leading, spacing: 28) {
        // Default: furigana in secondary, romaji in tertiary.
        RubyText(verbatim: sentence)

        // Furigana and romaji colored separately from the text.
        RubyText(verbatim: sentence)
            .foregroundStyle(.primary, .red, .blue)

        // A single style tints everything; the levels derive from it.
        RubyText(verbatim: sentence)
            .foregroundStyle(.indigo)

        // Everything in the text color, like printed books.
        RubyText(verbatim: sentence)
            .foregroundStyle(.primary, .primary, .primary)
    }
    .font(.title3)
    .rubyStyle([.furigana, .romaji])
    .padding()
}

#Preview("Animated style") {
    @Previewable @State var style: RubyStyle = .furigana

    VStack(alignment: .leading, spacing: 24) {
        RubyText(verbatim: "{吾輩|わがはい}は{猫|ねこ}である。{名前|なまえ}はまだ{無|な}い。")
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
