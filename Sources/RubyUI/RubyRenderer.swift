import RubyCore
import SwiftUI

/// Draws text normally, then draws furigana above and romaji below the
/// annotated ranges, and emphasizes the word a `RubyReader` is speaking.
struct RubyRenderer: TextRenderer {
    let metrics: RubyMetrics
    /// Annotation data for each paragraph of the text.
    let paragraphs: [RubyParagraph]
    /// How strongly furigana and romaji are shown, from 0 to 1. Values in
    /// between occur while a style change animates.
    let furigana: CGFloat
    let romaji: CGFloat
    var emphasis: RubyEmphasisState?

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
        var above: [Fragment] = []
        var below: [Fragment] = []
        // Bounds of the spoken word on each line it appears on.
        var emphasizedLines: [Int: CGRect] = [:]

        for (lineNumber, line, paragraph, start) in layout.rubyParagraphLines {
            guard paragraphs.indices.contains(paragraph) else {
                for run in line { context.draw(run) }
                continue
            }
            let data = paragraphs[paragraph]
            // Annotations take their vertical position from the line, not
            // from individual glyphs, whose bounds vary (tracked runs, font
            // fallback), so everything on a line shares one baseline.
            let lineBounds = line.typographicBounds.rect
            if !data.backgrounds.isEmpty {
                drawBackgrounds(data.backgrounds, on: line, paragraphStart: start, tracked: data.tracked, lineBounds: lineBounds, in: context)
            }

            let spokenRange = emphasis.flatMap { $0.paragraph == paragraph ? $0.range : nil }
            var emphasizedSlices: [(slice: Text.Layout.RunSlice, tracking: CGFloat)] = []
            var wordRect = CGRect.null

            for run in line {
                let offsets = run.characterIndices.map { start.distance(to: $0) }
                guard offsets.count == run.count else {
                    context.draw(run)
                    continue
                }
                func isSpoken(_ index: Int) -> Bool { spokenRange?.contains(offsets[index]) ?? false }

                // Draw glyphs in slices that share the same tracking. Tracking
                // pads after every glyph, so shift each slice by half of it
                // to center the glyphs in their widened boxes. Slices of the
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
                    let tracking = tracked?.tracking ?? 0
                    if spoken {
                        emphasizedSlices.append((slice, tracking))
                    } else {
                        var shifted = context
                        shifted.translateBy(x: tracking / 2, y: 0)
                        shifted.draw(slice)
                    }
                    lower = upper
                }

                // Collect the boxes that annotations and emphasis sit around.
                for index in 0..<run.count {
                    let aboveAnnotation = Self.item(at: offsets[index], in: data.above, range: \.range)
                    let belowAnnotation = Self.item(at: offsets[index], in: data.below, range: \.range)
                    let spoken = isSpoken(index)
                    guard aboveAnnotation != nil || belowAnnotation != nil || spoken else { continue }

                    let glyph = Self.glyphBox(in: run, at: index, offset: offsets[index], tracked: data.tracked)
                    let rect = CGRect(x: glyph.minX, y: lineBounds.minY, width: glyph.width, height: lineBounds.height)
                    if spoken { wordRect = wordRect.union(rect) }
                    if let aboveAnnotation {
                        Self.add(aboveAnnotation, rect: rect, paragraph: paragraph, line: lineNumber, to: &above)
                    }
                    if let belowAnnotation {
                        Self.add(belowAnnotation, rect: rect, paragraph: paragraph, line: lineNumber, to: &below)
                    }
                }
            }

            if let emphasis, !emphasizedSlices.isEmpty {
                drawSpokenWord(emphasizedSlices, in: wordRect, emphasis: emphasis, context: context)
                emphasizedLines[lineNumber] = wordRect
            }
        }

        // While a style change animates, annotations fade with their
        // strength and slide out from behind the base text. Sliding by the
        // full reserved height keeps them inside the space reserved so far,
        // so they never spill onto neighboring views.
        let slide = metrics.reservedHeight
        if furigana > 0 {
            var layer = context
            layer.opacity = furigana
            layer.translateBy(x: 0, y: (1 - furigana) * slide)
            for (text, fragment, isSplit) in Self.pieces(of: above) {
                var annotationContext = layer
                annotationContext.opacity *= fragment.annotation.opacity
                let tinted = emphasize(fragment, in: &annotationContext, lines: emphasizedLines)
                drawFurigana(text, over: fragment.rect, spread: !isSplit, tinted: tinted, color: fragment.annotation.color, in: &annotationContext)
            }
        }
        if romaji > 0 {
            var layer = context
            layer.opacity = romaji
            layer.translateBy(x: 0, y: -(1 - romaji) * slide)
            for (text, fragment, _) in Self.pieces(of: below) {
                var annotationContext = layer
                annotationContext.opacity *= fragment.annotation.opacity
                let tinted = emphasize(fragment, in: &annotationContext, lines: emphasizedLines)
                var resolved = annotationContext.resolve(Text(verbatim: text).font(metrics.annotationFont))
                // Romaji use the tertiary foreground style, so
                // `.foregroundStyle(_:_:_:)` can give them their own color,
                // unless the word they belong to is colored.
                resolved.shading = if tinted {
                    .style(.tint)
                } else if let color = fragment.annotation.color {
                    .color(color)
                } else {
                    .style(.tertiary)
                }
                let point = CGPoint(x: fragment.rect.midX, y: fragment.rect.maxY + metrics.gap)
                annotationContext.draw(resolved, at: point, anchor: .top)
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
            rect.origin.y -= metrics.reservedHeight * furigana
            rect.size.height += metrics.reservedHeight * (furigana + romaji)
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
        _ slices: [(slice: Text.Layout.RunSlice, tracking: CGFloat)],
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
            box.origin.y -= metrics.reservedHeight * furigana
            box.size.height += metrics.reservedHeight * (furigana + romaji)
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
            for item in slices { Self.draw(item.slice, tracking: item.tracking, in: context) }
            return
        }

        // Draw the glyphs into a layer, then paint the tint only where the
        // glyphs are, using the source-atop blend mode.
        context.drawLayer { layer in
            for item in slices { Self.draw(item.slice, tracking: item.tracking, in: layer) }
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

    /// The box of the glyph at `index`, including tracking added for
    /// annotations but not word spacing after it, so readings, highlights,
    /// and backgrounds stay centered on the glyph.
    private static func glyphBox(
        in run: Text.Layout.Run,
        at index: Int,
        offset: Int,
        tracked: [RubyTrackedRange]
    ) -> CGRect {
        var box = run[index..<(index + 1)].typographicBounds.rect
        if let gap = item(at: offset, in: tracked, range: \.range)?.gap, gap > 0 {
            box.size.width = max(box.width - gap, 0)
        }
        return box
    }

    private static func draw(_ slice: Text.Layout.RunSlice, tracking: CGFloat, in context: GraphicsContext) {
        var context = context
        context.translateBy(x: tracking / 2, y: 0)
        context.draw(slice)
    }

    // MARK: Annotations

    /// Draws a reading above `rect`. Like HTML `<ruby>`, a reading narrower
    /// than its base is spread across it.
    private func drawFurigana(
        _ text: String,
        over rect: CGRect,
        spread: Bool,
        tinted: Bool,
        color: Color?,
        in context: inout GraphicsContext
    ) {
        var tracking: CGFloat = 0
        if spread, text.count > 1 {
            let natural = context.resolve(Text(verbatim: text).font(metrics.annotationFont))
            let width = natural.measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).width
            tracking = max(0, rect.width - width) / CGFloat(text.count)
        }
        var resolved = context.resolve(
            Text(verbatim: text).font(metrics.annotationFont).tracking(tracking)
        )
        // Furigana use the secondary foreground style, so
        // `.foregroundStyle(_:_:)` can color them separately from the text,
        // unless the word they belong to is colored.
        resolved.shading = if tinted {
            .style(.tint)
        } else if let color {
            .color(color)
        } else {
            .style(.secondary)
        }
        // Offset by half the trailing tracking so the visible glyphs are centered.
        let point = CGPoint(x: rect.midX + tracking / 2, y: rect.minY - metrics.gap)
        context.draw(resolved, at: point, anchor: .bottom)
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
