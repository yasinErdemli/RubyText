import RubyCore
import SwiftUI

/// Draws text normally, then draws furigana above and romaji above or
/// below the annotated ranges, and emphasizes the word a `RubyReader` is
/// speaking.
struct RubyRenderer: TextRenderer {
    let metrics: RubyMetrics
    /// Annotation data for each paragraph of the text.
    let paragraphs: [RubyParagraph]
    /// How strongly furigana, romaji above the text, and romaji below it
    /// are shown, from 0 to 1. Values in between occur while a style
    /// change animates.
    let furigana: CGFloat
    let romajiAbove: CGFloat
    let romajiBelow: CGFloat
    var emphasis: RubyEmphasisState?

    /// How much of the reserved height annotations take above and below
    /// each line.
    private var above: CGFloat { min(1, furigana + romajiAbove) }
    private var below: CGFloat { romajiBelow }

    /// How much the spoken word scales up with `.grow`.
    private static let growScale: CGFloat = 0.12

    // Keeps annotations on the first and last lines, and a grown word, from
    // being clipped. This must not depend on whether a word is emphasized or
    // on the animating strengths, and stays vertical only: changing it alters
    // the width the text is laid out in, which makes lines rewrap.
    var displayPadding: EdgeInsets {
        let padding = metrics.reservedHeight * 1.5
        return EdgeInsets(top: padding, leading: 0, bottom: padding, trailing: 0)
    }

    /// The part of an annotated range that sits on one line.
    private struct Fragment {
        let annotation: RubyAnnotation
        let paragraph: Int
        let line: Int
        var rect: CGRect
        var glyphCount: Int
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // Fragments in layout order. An annotation normally yields one
        // fragment, but gets one per line if its base text wraps.
        var furiganaFragments: [Fragment] = []
        var romajiFragments: [Fragment] = []
        // Bounds of the spoken word on each line it appears on.
        var emphasizedLines: [Int: CGRect] = [:]
        // Annotations may extend past their words, but not past the text.
        // Where the text starts and ends: the line bounds, and the end of
        // each line's last glyph, since the bounds may extend past it.
        let lineRects = layout.map(\.typographicBounds.rect)
        let leadingEdge = lineRects.map(\.minX).min() ?? 0
        var trailingEdge = leadingEdge

        for (lineNumber, line, paragraph, start) in layout.rubyParagraphLines {
            guard paragraphs.indices.contains(paragraph) else {
                for run in line { context.draw(run) }
                continue
            }
            let data = paragraphs[paragraph]
            if let run = line.last, run.count > 0, let index = run.characterIndices.last {
                let box = Self.glyphBox(in: run, at: run.count - 1, offset: start.distance(to: index), tracked: data.tracked)
                trailingEdge = max(trailingEdge, box.maxX)
            }
            // Annotations take their vertical position from the line, not
            // from individual glyphs, whose bounds vary (tracked runs, font
            // fallback), so everything on a line shares one baseline.
            let lineBounds = line.typographicBounds.rect
            if !data.backgrounds.isEmpty {
                drawBackgrounds(data.backgrounds, on: line, paragraphStart: start, tracked: data.tracked, lineBounds: lineBounds, in: context)
            }

            let spokenRange = emphasis.flatMap { $0.paragraph == paragraph ? $0.range : nil }
            var emphasizedSlices: [(slice: Text.Layout.RunSlice, shift: CGFloat)] = []
            var wordRect = CGRect.null

            for run in line {
                let offsets = run.characterIndices.map { start.distance(to: $0) }
                guard offsets.count == run.count else {
                    context.draw(run)
                    continue
                }
                func isSpoken(_ index: Int) -> Bool { spokenRange?.contains(offsets[index]) ?? false }

                // Draw glyphs in slices that share the same spacing, each
                // shifted right within the space before it. Slices of the
                // spoken word are drawn afterwards, with emphasis.
                var lower = 0
                while lower < run.count {
                    let tracked = Self.item(at: offsets[lower], in: data.tracked, range: \.range)
                    let spoken = isSpoken(lower)
                    var upper = lower + 1
                    while upper < run.count,
                          isSpoken(upper) == spoken,
                          Self.item(at: offsets[upper], in: data.tracked, range: \.range)?.range == tracked?.range {
                        upper += 1
                    }
                    let slice = run[lower..<upper]
                    let shift = tracked?.shift ?? 0
                    if spoken {
                        emphasizedSlices.append((slice, shift))
                    } else {
                        Self.draw(slice, shift: shift, in: context)
                    }
                    lower = upper
                }

                // Collect the boxes that annotations and emphasis sit around.
                for index in 0..<run.count {
                    let reading = Self.item(at: offsets[index], in: data.furigana, range: \.range)
                    let romaji = Self.item(at: offsets[index], in: data.romaji, range: \.range)
                    let spoken = isSpoken(index)
                    guard reading != nil || romaji != nil || spoken else { continue }

                    let glyph = Self.glyphBox(in: run, at: index, offset: offsets[index], tracked: data.tracked)
                    let rect = CGRect(x: glyph.minX, y: lineBounds.minY, width: glyph.width, height: lineBounds.height)
                    if spoken { wordRect = wordRect.union(rect) }
                    if let reading {
                        Self.add(reading, rect: rect, paragraph: paragraph, line: lineNumber, to: &furiganaFragments)
                    }
                    if let romaji {
                        Self.add(romaji, rect: rect, paragraph: paragraph, line: lineNumber, to: &romajiFragments)
                    }
                }
            }

            if let emphasis, !emphasizedSlices.isEmpty {
                drawSpokenWord(emphasizedSlices, in: wordRect, emphasis: emphasis, context: context)
                emphasizedLines[lineNumber] = wordRect
            }
        }

        let edges = leadingEdge...max(leadingEdge, trailingEdge)

        // While a style change animates, annotations fade with their
        // strength and slide out from behind the base text. Sliding by the
        // full reserved height keeps them inside the space reserved so far,
        // so they never spill onto neighboring views.
        let slide = metrics.reservedHeight
        if furigana > 0 {
            var layer = context
            layer.opacity = furigana
            layer.translateBy(x: 0, y: (1 - furigana) * slide)
            let pieces = Self.pieces(of: furiganaFragments)
            // Readings of neighboring kanji (経済|政策) may touch; others
            // keep a little space.
            let centers = placeAnnotations(pieces, spreads: true, spacing: metrics.romajiSpacing / 2, within: edges, in: context)
            for ((text, fragment, isSplit), center) in zip(pieces, centers) {
                var annotationContext = layer
                annotationContext.opacity *= fragment.annotation.opacity
                let tinted = emphasize(fragment, in: &annotationContext, lines: emphasizedLines)
                drawFurigana(text, over: fragment.rect, at: center, scale: fragment.annotation.scale, spread: !isSplit && Self.spreads(text), tinted: tinted, color: fragment.annotation.color, in: &annotationContext)
            }
        }
        guard romajiAbove > 0 || romajiBelow > 0 else { return }
        let pieces = Self.pieces(of: romajiFragments)
        let centers = placeAnnotations(pieces, spreads: false, spacing: metrics.romajiSpacing, within: edges, in: context)
        // Romaji switching sides fade out on one and in on the other.
        for (strength, isAbove) in [(romajiAbove, true), (romajiBelow, false)] where strength > 0 {
            var layer = context
            layer.opacity = strength
            layer.translateBy(x: 0, y: (isAbove ? 1 : -1) * (1 - strength) * slide)
            for ((text, fragment, _), center) in zip(pieces, centers) {
                var annotationContext = layer
                annotationContext.opacity *= fragment.annotation.opacity
                let tinted = emphasize(fragment, in: &annotationContext, lines: emphasizedLines)
                // Romaji use the tertiary foreground style, so
                // `.foregroundStyle(_:_:_:)` can give them their own color,
                // unless the word they belong to is colored.
                let style: AnyShapeStyle = if tinted {
                    AnyShapeStyle(.tint)
                } else if let color = fragment.annotation.color {
                    AnyShapeStyle(color)
                } else {
                    AnyShapeStyle(.tertiary)
                }
                let resolved = annotationContext.resolve(metrics.annotationText(text).foregroundStyle(style))
                annotationContext.translateBy(
                    x: center,
                    y: isAbove ? fragment.rect.minY - metrics.gap : fragment.rect.maxY + metrics.gap
                )
                annotationContext.scaleBy(x: fragment.annotation.scale, y: 1)
                annotationContext.draw(resolved, at: .zero, anchor: isAbove ? .bottom : .top)
            }
        }
    }

    // MARK: Word Backgrounds

    /// Fills a rounded box behind each colored word on `line`, covering its
    /// annotations. Drawn before the glyphs so it sits underneath them.
    private func drawBackgrounds(
        _ items: [RubyColoredRange],
        on line: Text.Layout.Line,
        paragraphStart start: Text.Layout.CharacterIndex,
        tracked: [RubyTrackedRange],
        lineBounds: CGRect,
        in context: GraphicsContext
    ) {
        var boxes: [(range: Range<Int>, color: Color, rect: CGRect)] = []
        for run in line {
            let offsets = run.characterIndices.map { start.distance(to: $0) }
            guard offsets.count == run.count else { continue }
            for index in 0..<run.count {
                guard let item = Self.item(at: offsets[index], in: items, range: \.range) else { continue }
                let glyph = Self.glyphBox(in: run, at: index, offset: offsets[index], tracked: tracked)
                if let last = boxes.indices.last, boxes[last].range == item.range {
                    boxes[last].rect = boxes[last].rect.union(glyph)
                } else {
                    boxes.append((item.range, item.color, glyph))
                }
            }
        }

        for box in boxes {
            // Inset slightly so neighboring words read as separate boxes.
            var rect = CGRect(x: box.rect.minX, y: lineBounds.minY, width: box.rect.width, height: lineBounds.height)
                .insetBy(dx: metrics.gap * 0.5, dy: -metrics.gap * 0.5)
            rect.origin.y -= metrics.reservedHeight * above
            rect.size.height += metrics.reservedHeight * (above + below)
            // Lightened so text in the primary color stays readable.
            context.fill(
                RoundedRectangle(cornerRadius: metrics.reservedHeight * 0.3).path(in: rect),
                with: .color(box.color.opacity(0.25))
            )
        }
    }

    // MARK: Emphasis

    /// Draws the spoken word's glyphs on one line with the chosen effects.
    private func drawSpokenWord(
        _ slices: [(slice: Text.Layout.RunSlice, shift: CGFloat)],
        in rect: CGRect,
        emphasis: RubyEmphasisState,
        context: GraphicsContext
    ) {
        var context = context

        // The highlight isn't scaled with the word, so it stays clear of the
        // lines above and below.
        if emphasis.options.contains(.highlight) {
            // Cover the word's annotations too.
            var box = rect.insetBy(dx: -metrics.gap * 2, dy: -metrics.gap)
            box.origin.y -= metrics.reservedHeight * above
            box.size.height += metrics.reservedHeight * (above + below)
            // Use the background style if one is set, such as with
            // `.backgroundStyle(.yellow)`; otherwise a soft tint. The default
            // background (`nil`) is the system background, which would be
            // invisible behind text.
            let fill: GraphicsContext.Shading = if let style = context.environment.backgroundStyle {
                .style(style)
            } else {
                .style(.tint.opacity(0.2))
            }
            var highlight = context
            highlight.opacity *= emphasis.appear
            highlight.fill(RoundedRectangle(cornerRadius: metrics.reservedHeight * 0.4).path(in: box), with: fill)
        }
        applyGrow(to: &context, around: rect, emphasis: emphasis)

        let colorsGlyphs = !emphasis.options.isDisjoint(with: [.tint, .karaoke])
        guard colorsGlyphs else {
            for item in slices { Self.draw(item.slice, shift: item.shift, in: context) }
            return
        }

        // Draw the glyphs into a layer, then paint the tint only where the
        // glyphs are, using the source-atop blend mode.
        context.drawLayer { layer in
            for item in slices { Self.draw(item.slice, shift: item.shift, in: layer) }
            layer.blendMode = .sourceAtop

            // Generously cover glyph overhang beyond the typographic bounds.
            let cover = rect.insetBy(dx: -rect.height, dy: -rect.height)
            if emphasis.options.contains(.tint) {
                // With karaoke, the unsung part gets a lighter tint.
                let opacity = emphasis.options.contains(.karaoke) ? 0.45 : 1
                layer.fill(Rectangle().path(in: cover), with: .style(.tint.opacity(opacity)))
            }
            if emphasis.options.contains(.karaoke) {
                var swept = cover
                swept.size.width = (rect.minX - cover.minX) + rect.width * emphasis.progress
                layer.fill(Rectangle().path(in: swept), with: .style(.tint))
            }
        }
    }

    /// If `fragment` belongs to the spoken word, applies its grow transform
    /// to `context` and returns whether the annotation should be tinted.
    private func emphasize(_ fragment: Fragment, in context: inout GraphicsContext, lines: [Int: CGRect]) -> Bool {
        guard let emphasis,
              fragment.paragraph == emphasis.paragraph,
              fragment.annotation.range.overlaps(emphasis.range),
              let wordRect = lines[fragment.line]
        else { return false }
        applyGrow(to: &context, around: wordRect, emphasis: emphasis)
        return !emphasis.options.isDisjoint(with: [.tint, .karaoke])
    }

    private func applyGrow(to context: inout GraphicsContext, around rect: CGRect, emphasis: RubyEmphasisState) {
        guard emphasis.options.contains(.grow) else { return }
        let scale = 1 + Self.growScale * emphasis.appear
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.midX, y: -rect.midY)
    }

    /// The box of the glyph at `index` where it's drawn, without the space
    /// added around it, so readings, highlights, and backgrounds stay
    /// centered on the glyph.
    private static func glyphBox(
        in run: Text.Layout.Run,
        at index: Int,
        offset: Int,
        tracked: [RubyTrackedRange]
    ) -> CGRect {
        var box = run[index..<(index + 1)].typographicBounds.rect
        if let spacing = item(at: offset, in: tracked, range: \.range) {
            box.origin.x += spacing.shift
            box.size.width = max(box.width - spacing.tracking, 0)
        }
        return box
    }

    private static func draw(_ slice: Text.Layout.RunSlice, shift: CGFloat, in context: GraphicsContext) {
        var context = context
        context.translateBy(x: shift, y: 0)
        context.draw(slice)
    }

    /// Where to center each annotation: over its base, unless that would
    /// put it past the edge of the text, such as at the start of a wrapped
    /// line; then it moves inside, and neighbors on its line move along so
    /// none overlap.
    ///
    /// - Parameter spreads: Whether readings narrower than their base are
    ///   spread across it, taking its full width.
    private func placeAnnotations(
        _ pieces: [(String, Fragment, Bool)],
        spreads: Bool,
        spacing: CGFloat,
        within edges: ClosedRange<CGFloat>,
        in context: GraphicsContext
    ) -> [CGFloat] {
        let widths = pieces.map { text, fragment, isSplit in
            let natural = context.resolve(metrics.annotationText(text))
                .measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).width * fragment.annotation.scale
            return spreads && !isSplit && text.count > 1 && Self.spreads(text) ? max(natural, fragment.rect.width) : natural
        }
        var centers = pieces.map { $0.1.rect.midX }
        for indices in Dictionary(grouping: pieces.indices, by: { pieces[$0].1.line }).values {
            let order = indices.sorted { centers[$0] < centers[$1] }
            // Space between two annotations, unless their bases touch.
            func space(_ first: Int, _ second: Int) -> CGFloat {
                pieces[second].1.rect.minX - pieces[first].1.rect.maxX > 0.5 || !spreads ? spacing : 0
            }
            // Left to right, keep each clear of the edge and the one before.
            func clearLeadingEdge() {
                var previous: (index: Int, right: CGFloat)?
                for index in order {
                    let limit = previous.map { $0.right + space($0.index, index) } ?? edges.lowerBound
                    let left = max(centers[index] - widths[index] / 2, limit)
                    centers[index] = left + widths[index] / 2
                    previous = (index, left + widths[index])
                }
            }
            clearLeadingEdge()
            // Then right to left, pulling back any past the far edge.
            var next: (index: Int, left: CGFloat)?
            for index in order.reversed() {
                let limit = next.map { $0.left - space(index, $0.index) } ?? edges.upperBound
                let right = min(centers[index] + widths[index] / 2, limit)
                centers[index] = right - widths[index] / 2
                next = (index, right - widths[index])
            }
            // If they don't fit between the edges, the leading one wins:
            // there's usually room after the text, never before it.
            clearLeadingEdge()
        }
        return centers
    }

    // MARK: Annotations

    /// Draws a reading above `rect`. Like HTML `<ruby>`, a reading narrower
    /// than its base is spread across it.
    private func drawFurigana(
        _ text: String,
        over rect: CGRect,
        at center: CGFloat,
        scale: CGFloat,
        spread: Bool,
        tinted: Bool,
        color: Color?,
        in context: inout GraphicsContext
    ) {
        let natural = context.resolve(metrics.annotationText(text))
        let width = natural.measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).width
        var tracking: CGFloat = 0
        if spread, scale == 1, text.count > 1 {
            tracking = max(0, rect.width - width) / CGFloat(text.count)
        }
        // Furigana use the secondary foreground style, so
        // `.foregroundStyle(_:_:)` can color them separately from the text,
        // unless the word they belong to is colored. The style is part of
        // the text: over a material, resolved text ignores its shading.
        let style: AnyShapeStyle = if tinted {
            AnyShapeStyle(.tint)
        } else if let color {
            AnyShapeStyle(color)
        } else {
            AnyShapeStyle(.secondary)
        }
        let resolved = context.resolve(
            metrics.annotationText(text).tracking(tracking).foregroundStyle(style)
        )
        // Offset by half the trailing tracking so the visible glyphs are centered.
        var drawing = context
        drawing.translateBy(x: center + tracking / 2, y: rect.minY - metrics.gap)
        drawing.scaleBy(x: scale, y: 1)
        drawing.draw(resolved, at: .zero, anchor: .bottom)
    }

    /// Whether a reading narrower than its base may be spread across it,
    /// as kana are in `<ruby>`. Romaji furigana keep their letter spacing.
    private static func spreads(_ text: String) -> Bool {
        !text.contains(where: \.isASCII)
    }

    private static func add(
        _ annotation: RubyAnnotation,
        rect: CGRect,
        paragraph: Int,
        line: Int,
        to fragments: inout [Fragment]
    ) {
        if let last = fragments.indices.last,
           fragments[last].annotation.id == annotation.id,
           fragments[last].line == line {
            fragments[last].rect = fragments[last].rect.union(rect)
            fragments[last].glyphCount += 1
        } else {
            fragments.append(Fragment(annotation: annotation, paragraph: paragraph, line: line, rect: rect, glyphCount: 1))
        }
    }

    /// Kana that can't begin a mora on their own.
    private static let attachesToPrevious = Set("ぁぃぅぇぉゃゅょゎっんァィゥェォャュョヮッンー")

    private static let romajiVowels = Set("aeiouāīūēōâîûêô")

    /// Whether romaji may be split before `index`: after a vowel, after a
    /// syllabic n (ben|kyou), or between doubled consonants (chot|to).
    /// Always true for non-Latin text, which the kana rule handles.
    private static func isRomajiBreak(in text: [Character], at index: Int) -> Bool {
        guard index > 0, index < text.count else { return true }
        let previous = Character(text[index - 1].lowercased())
        let next = Character(text[index].lowercased())
        guard previous.isASCII || romajiVowels.contains(previous),
              next.isASCII || romajiVowels.contains(next),
              previous.isLetter, next.isLetter
        else { return true }

        let nextIsVowel = romajiVowels.contains(next)
        if romajiVowels.contains(previous) { return true }
        if previous == "n" { return !nextIsVowel && next != "y" }
        return previous == next
    }

    /// Binary search for the item whose range covers a UTF-16 offset.
    private static func item<T>(at offset: Int, in items: [T], range: KeyPath<T, Range<Int>>) -> T? {
        var low = 0
        var high = items.count
        while low < high {
            let mid = (low + high) / 2
            let itemRange = items[mid][keyPath: range]
            if offset < itemRange.lowerBound {
                high = mid
            } else if offset >= itemRange.upperBound {
                low = mid + 1
            } else {
                return items[mid]
            }
        }
        return nil
    }

    /// Pairs each fragment with the annotation text to draw for it. When the
    /// base wraps, the text is divided in proportion to how many base
    /// characters each line holds, so it isn't duplicated.
    private static func pieces(of fragments: [Fragment]) -> [(String, Fragment, Bool)] {
        var result: [(String, Fragment, Bool)] = []
        var index = 0
        while index < fragments.count {
            let id = fragments[index].annotation.id
            var end = index
            while end + 1 < fragments.count, fragments[end + 1].annotation.id == id { end += 1 }

            if index == end {
                result.append((fragments[index].annotation.text, fragments[index], false))
            } else {
                let text = Array(fragments[index].annotation.text)
                let baseCount = max(fragments[index].annotation.baseCount, 1)
                var consumedBase = 0
                var start = 0
                for position in index...end {
                    let fragment = fragments[position]
                    consumedBase += fragment.glyphCount
                    // Rounding down tends to match how readings divide over
                    // kanji (べん|きょう, し|けん, ben|kyou). The last piece
                    // takes whatever remains.
                    var stop = Int((Double(text.count * consumedBase) / Double(baseCount)).rounded(.down))
                    stop = position == end ? text.count : min(max(stop, start), text.count)
                    // Don't start a piece with a kana that belongs to the
                    // previous mora, such as ょ in きょ or ん, or split romaji
                    // inside a syllable (na|i, not n|ai).
                    while stop < text.count, position != end,
                          Self.attachesToPrevious.contains(text[stop]) || !Self.isRomajiBreak(in: text, at: stop) {
                        stop += 1
                    }
                    result.append((String(text[start..<stop]), fragment, true))
                    start = stop
                }
            }
            index = end + 1
        }
        return result
    }
}

extension Text.Layout {
    /// Each line with text, with its line number, the paragraph it belongs
    /// to, and where that paragraph starts.
    ///
    /// `characterIndices` are UTF-16 offsets relative to the paragraph, so
    /// this tracks which paragraph each line belongs to: a new one starts
    /// after an empty line, or when the indices restart. Empty lines have no
    /// runs and are left out.
    var rubyParagraphLines: [(lineNumber: Int, line: Line, paragraph: Int, start: CharacterIndex)] {
        var result: [(lineNumber: Int, line: Line, paragraph: Int, start: CharacterIndex)] = []
        var paragraph = -1
        var paragraphStart: CharacterIndex?
        var previousLast: CharacterIndex?
        for (lineNumber, line) in enumerated() {
            let indices = line.flatMap(\.characterIndices)
            guard let first = indices.min(), let last = indices.max() else {
                paragraph += 1
                previousLast = nil
                continue
            }
            if previousLast.map({ first <= $0 }) ?? true {
                paragraph += 1
                paragraphStart = first
            }
            previousLast = last
            if let paragraphStart {
                result.append((lineNumber, line, paragraph, paragraphStart))
            }
        }
        return result
    }
}
