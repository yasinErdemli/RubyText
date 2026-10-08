import RubyCore
import SwiftUI

/// Japanese text that can show furigana above and romaji below its words.
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
/// Pass `RubySegment`s directly to show readings from your own data, with
/// no on-device analysis:
///
///     RubyText(segments: mySegments)
///
/// Changing the style animates: annotations fade in or out, and the line
/// spacing and letter spacing they need ease to their new values.
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
/// Readings come from MeCab with IPAdic unless you choose another analyzer
/// with `rubyAnalyzer(_:)`.
///
/// Annotations are drawn by `RubyRenderer` and aren't part of the text
/// content, so selection, copy, and VoiceOver only see the base text.
public struct RubyText: View {
    private enum Input {
        case markup(String)
        case segments([RubySegment])
    }
    private let input: Input

    @Environment(\.rubyAnalyzer) private var analyzer
    @Environment(\.rubyStyle) private var style
    @Environment(\.rubyFuriganaFilter) private var furiganaFilter
    @Environment(\.rubyDigitReadingsHidden) private var digitReadingsHidden
    @Environment(\.rubySpacing) private var spacing
    @Environment(\.rubyWordColoring) private var wordColoring
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
        // first time.
        let content: RubyContent = switch input {
        case .markup(let markup): .content(for: markup, analyzer: analyzer)
        case .segments(let segments): .content(for: segments)
        }
        RubyTextContent(
            content: content,
            furigana: style.contains(.furigana) ? 1 : 0,
            romaji: style.contains(.romaji) ? 1 : 0,
            readingVisibility: readingVisibility(in: content),
            romajiVisibility: romajiVisibility(in: content),
            wordGaps: wordGaps(in: content),
            // Computed here, not inside the animated content view, so
            // style transitions don't re-run vocabulary and JLPT lookups
            // on every frame.
            textColors: RubyTextContent.coloredRanges(wordColoring.text, in: content),
            backgroundColors: RubyTextContent.coloredRanges(wordColoring.background, in: content),
            selectedRange: selectedWord?.range,
            selectedWord: $selectedWord,
            selectedRect: $selectedRect
        )
        .popover(item: $selectedWord, attachmentAnchor: .rect(.rect(selectedRect))) { word in
            RubyWordDetailView(word: word)
                .presentationCompactAdaptation(.popover)
        }
        // Annotations slide and lines move apart, so with Reduce Motion the
        // style switches without animating.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: style)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: furiganaFilter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: digitReadingsHidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: spacing)
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

    /// Whether each word's romaji shows, one value per word with romaji, in
    /// content order. Romaji hide over numbers in digits along with their
    /// furigana, so a number shows both readings or neither.
    private func romajiVisibility(in content: RubyContent) -> RubyAnimatableVector {
        RubyAnimatableVector(values: content.words.filter { $0.romaji != nil }.map { word in
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
        let boundaries = spacing.boundaries(in: content)
        guard !boundaries.isEmpty else { return .zero }
        var values = [Double](repeating: 0, count: content.string.utf16.count + 1)
        for offset in boundaries { values[offset] = spacing.width }
        return RubyAnimatableVector(values: values)
    }
}

extension EnvironmentValues {
    /// Finds words and readings for `RubyText` views. MeCab with IPAdic by
    /// default.
    @Entry var rubyAnalyzer: any RubyAnalyzer = RubyMeCabAnalyzer.shared
}

extension View {
    /// Sets the analyzer `RubyText` views in this hierarchy use to find
    /// words and readings, such as one backed by another dictionary.
    ///
    /// Give a `RubyReader` reading the same text the same analyzer, so the
    /// phrases it emphasizes match the views' words.
    public func rubyAnalyzer(_ analyzer: any RubyAnalyzer) -> some View {
        environment(\.rubyAnalyzer, analyzer)
    }
}

/// Draws `RubyText` with each kind of annotation at a strength from 0
/// (hidden, no space reserved) to 1 (fully shown). SwiftUI interpolates the
/// strengths when the style changes, so everything eases into place.
@Animatable
private struct RubyTextContent: View {
    @AnimatableIgnored let content: RubyContent
    var furigana: CGFloat
    var romaji: CGFloat
    var readingVisibility: RubyAnimatableVector
    var romajiVisibility: RubyAnimatableVector
    var wordGaps: RubyAnimatableVector
    /// Precomputed by `RubyText`, so word coloring doesn't re-run its
    /// lookups on every frame of a style animation.
    @AnimatableIgnored let textColors: [RubyColoredRange]
    @AnimatableIgnored let backgroundColors: [RubyColoredRange]

    @AnimatableIgnored @Environment(\.rubyReader) private var reader
    @AnimatableIgnored @Environment(\.rubyEmphasis) private var emphasisOptions
    @AnimatableIgnored @Environment(\.rubyLineBreaking) private var lineBreaking
    @AnimatableIgnored @Environment(\.rubyShowsWordDetails) private var showsWordDetails
    @AnimatableIgnored @Environment(\.rubyWordTapAction) private var wordTapAction
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

    var body: some View {
        if furigana == 0 && romaji == 0 && reader == nil && textColors.isEmpty && backgroundColors.isEmpty
            && wordGaps.isZero && !isTappable {
            Text(Self.plainText(content.string, lineBreaking: lineBreaking))
        } else {
            let metrics = RubyMetrics(font: font ?? .body, in: fontResolutionContext)
            let layout = RubyLayout(
                measurements: .measurements(for: content, metrics: metrics),
                furigana: furigana,
                romaji: romaji,
                readingVisibility: readingVisibility,
                romajiVisibility: romajiVisibility,
                wordGaps: wordGaps,
                fontSize: metrics.fontSize,
                lineBreaking: lineBreaking,
                textColors: textColors,
                backgrounds: backgrounds()
            )

            if let reader {
                // Only tick while this text is the one being read.
                let isReadingThis = reader.text == content.string && reader.isSpeaking
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
        let above = metrics.reservedHeight * furigana
        let below = metrics.reservedHeight * romaji

        return Text(layout.text)
            .lineSpacing(above + below)
            .padding(.top, above)
            .padding(.bottom, below)
            .textRenderer(RubyRenderer(
                metrics: metrics,
                paragraphs: layout.paragraphs,
                furigana: furigana,
                romaji: romaji,
                emphasis: emphasis
            ))
            .modifier(RubyWordTapping(isEnabled: isTappable) { point, geometry in
                tapWord(at: point, in: geometry, layout: layout, metrics: metrics)
            })
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
              let range = content.dictionaryWords.first(where: { $0.contains(offset) })
        else {
            selectedWord.wrappedValue = nil
            return
        }
        let word = RubyWordInfo.info(for: range, in: content)
        wordTapAction?(word)
        if showsWordDetails {
            selectedRect.wrappedValue = wordRect(range, in: geometry, layout: layout, metrics: metrics) ?? .zero
            selectedWord.wrappedValue = word
        }
    }

    /// The UTF-16 offset in the text of the character at `point`. A tap on
    /// a word's furigana or romaji counts as a tap on the word.
    private func characterOffset(at point: CGPoint, in geometry: RubyTextGeometry, layout: RubyLayout, metrics: RubyMetrics) -> Int? {
        let point = CGPoint(x: point.x - geometry.origin.x, y: point.y - geometry.origin.y)
        let above = metrics.reservedHeight * furigana
        let below = metrics.reservedHeight * romaji
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
            let above = metrics.reservedHeight * furigana
            let below = metrics.reservedHeight * romaji
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
    private static func plainText(_ string: String, lineBreaking: RubyLineBreaking) -> AttributedString {
        var text = AttributedString(string)
        text.languageIdentifier = lineBreaking.languageIdentifier
        return text
    }

    /// The ranges `colors` colors, with neighboring words of the same color
    /// merged so a compound like 日本|語 gets one background.
    fileprivate static func coloredRanges(_ colors: RubyWordColors?, in content: RubyContent) -> [RubyColoredRange] {
        guard let colors else { return [] }
        var ranges: [RubyColoredRange] = []
        for (word, color) in zip(content.words, colors.colors(for: content.words, in: content.string)) {
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
        let placed = layout.place(word.range)
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

/// Captures the layout SwiftUI made for the text, and reports taps with
/// it so the tapped word can be found.
private struct RubyWordTapping: ViewModifier {
    let isEnabled: Bool
    let onTap: (CGPoint, RubyTextGeometry) -> Void

    @State private var geometry: RubyTextGeometry?

    func body(content: Content) -> some View {
        content
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
private final class RubyMeasurements {
    struct Furigana {
        /// Index among all of the content's readings, for its visibility.
        let source: Int
        /// Characters the reading sits over.
        let characters: Range<Int>
        /// UTF-16 range of those characters.
        let range: Range<Int>
        let text: String
        /// How much wider the reading is than its base text.
        let extraWidth: CGFloat
    }

    struct Romaji {
        /// Index among the content's words with romaji, for
        /// `romajiVisibility`.
        let source: Int
        let characters: Range<Int>
        let range: Range<Int>
        let text: String
        let baseWidth: CGFloat
        /// Width of the romaji plus spacing from its neighbors.
        let width: CGFloat
    }

    let characters: [Character]
    /// UTF-16 offset where each character starts, plus the end offset.
    let starts: [Int]
    let furigana: [Furigana]
    let romaji: [Romaji]
    /// UTF-16 offset where each paragraph starts.
    let paragraphStarts: [Int]

    private static let cache = NSCache<NSString, RubyMeasurements>()

    static func measurements(for content: RubyContent, metrics: RubyMetrics) -> RubyMeasurements {
        let key = (metrics.cacheKey + "\n" + content.string) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let measurements = RubyMeasurements(content: content, metrics: metrics)
        cache.setObject(measurements, forKey: key)
        return measurements
    }

    private init(content: RubyContent, metrics: RubyMetrics) {
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

        var furigana: [Furigana] = []
        var romaji: [Romaji] = []
        var source = 0
        var romajiSource = 0
        for word in content.words {
            for reading in word.furigana {
                defer { source += 1 }
                let indices = characterRange(reading.range)
                guard !indices.isEmpty else { continue }
                furigana.append(Furigana(
                    source: source,
                    characters: indices,
                    range: reading.range,
                    text: reading.text,
                    extraWidth: metrics.annotationWidth(of: reading.text)
                        - metrics.baseWidth(of: String(characters[indices]))
                ))
            }
            if let text = word.romaji {
                defer { romajiSource += 1 }
                let indices = characterRange(word.range)
                guard !indices.isEmpty else { continue }
                romaji.append(Romaji(
                    source: romajiSource,
                    characters: indices,
                    range: word.range,
                    text: text,
                    baseWidth: metrics.baseWidth(of: String(characters[indices])),
                    width: metrics.annotationWidth(of: text) + metrics.romajiSpacing
                ))
            }
        }

        var paragraphStarts = [0]
        for (index, character) in characters.enumerated() where character.isNewline && character != "\u{2028}" {
            paragraphStarts.append(starts[index + 1])
        }

        self.characters = characters
        self.starts = starts
        self.furigana = furigana
        self.romaji = romaji
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

/// The attributed text and renderer data for one pair of annotation strengths.
private struct RubyLayout {
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
        lineBreaking: RubyLineBreaking,
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

        // The renderer can't change layout, so annotations wider than their
        // base text get room by adding tracking to the base characters,
        // scaled by how strongly each kind of annotation is shown.
        var tracking = [CGFloat](repeating: 0, count: characters.count)
        if furigana > 0 {
            for reading in measurements.furigana where reading.extraWidth > 0 {
                let share = reading.extraWidth * furigana * readingVisibility.value(at: reading.source, default: 1)
                    / CGFloat(reading.characters.count)
                for index in reading.characters { tracking[index] += share }
            }
        }
        if romaji > 0 {
            for word in measurements.romaji {
                // Measure the word as already widened for furigana.
                let width = word.baseWidth + word.characters.reduce(0) { $0 + tracking[$1] }
                let extra = word.width - width
                guard extra > 0 else { continue }
                let share = extra * romaji * romajiVisibility.value(at: word.source, default: 1)
                    / CGFloat(word.characters.count)
                for index in word.characters { tracking[index] += share }
            }
        }

        // Word spacing pads after the last character of a word, on top of
        // any tracking for annotations.
        let gaps = characters.indices.map { wordGaps.value(at: starts[$0 + 1], default: 0) * fontSize }

        // Build one flat attributed string with a run per tracking value and color.
        var text = AttributedString()
        var tracked: [RubyTrackedRange] = []
        var lower = 0
        while lower < characters.count {
            var upper = lower + 1
            while upper < characters.count, tracking[upper] == tracking[lower], gaps[upper] == gaps[lower],
                  colors[upper] == colors[lower] {
                upper += 1
            }
            var piece = AttributedString(String(characters[lower..<upper]))
            piece.foregroundColor = colors[lower]
            if tracking[lower] + gaps[lower] > 0 {
                piece.tracking = tracking[lower] + gaps[lower]
                tracked.append(RubyTrackedRange(range: starts[lower]..<starts[upper], tracking: tracking[lower], gap: gaps[lower]))
            }
            text.append(piece)
            lower = upper
        }
        // The language decides where lines may break, such as only between
        // phrases. It's a standard attribute, so copying still works.
        text.languageIdentifier = lineBreaking.languageIdentifier
        self.text = text

        // Layout character indices restart at each paragraph, so ranges are
        // converted to paragraph-relative offsets.
        let paragraphStarts = measurements.paragraphStarts
        self.paragraphStarts = paragraphStarts
        var paragraphs = [RubyParagraph](repeating: RubyParagraph(), count: paragraphStarts.count)
        for item in tracked {
            let placed = Self.place(item.range, paragraphStarts: paragraphStarts)
            paragraphs[placed.paragraph].tracked.append(RubyTrackedRange(range: placed.range, tracking: item.tracking, gap: item.gap))
        }
        if furigana > 0 {
            for (id, reading) in measurements.furigana.enumerated() {
                let visibility = readingVisibility.value(at: reading.source, default: 1)
                guard visibility > 0 else { continue }
                let placed = Self.place(reading.range, paragraphStarts: paragraphStarts)
                paragraphs[placed.paragraph].above.append(RubyAnnotation(
                    id: id, text: reading.text, range: placed.range, baseCount: reading.characters.count,
                    color: colors[reading.characters.lowerBound],
                    opacity: visibility
                ))
            }
        }
        if romaji > 0 {
            for (id, word) in measurements.romaji.enumerated() {
                let visibility = romajiVisibility.value(at: word.source, default: 1)
                guard visibility > 0 else { continue }
                let placed = Self.place(word.range, paragraphStarts: paragraphStarts)
                paragraphs[placed.paragraph].below.append(RubyAnnotation(
                    id: id, text: word.text, range: placed.range, baseCount: word.characters.count,
                    color: colors[word.characters.lowerBound],
                    opacity: visibility
                ))
            }
        }
        for item in backgrounds {
            let placed = Self.place(item.range, paragraphStarts: paragraphStarts)
            paragraphs[placed.paragraph].backgrounds.append(RubyColoredRange(range: placed.range, color: item.color))
        }
        self.paragraphs = paragraphs
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

#Preview("Ruby styles") {
    let sentence = "吾輩は猫である。名前はまだ無い。日本語を勉強しています。"

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

            // Manual readings override automatic ones; multiple paragraphs.
            RubyText(verbatim: "{今日|きょう}は{東京|とうきょう}へ{行|い}きたい。\n\nコーヒーを飲みたい。")
                .font(.title2.bold())
                .rubyStyle([.furigana, .romaji])

            // Long word forced to wrap: its reading is split, not duplicated.
            RubyText(verbatim: "きのう日本語能力試験を受けた。")
                .frame(width: 160, alignment: .leading)
                .rubyStyle()
        }
        .textSelection(.enabled)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Colors") {
    let sentence = "吾輩は猫である。名前はまだ無い。"

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
        RubyText(verbatim: "吾輩は猫である。名前はまだ無い。")
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
