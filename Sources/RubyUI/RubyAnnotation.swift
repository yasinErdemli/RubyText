import RubyCore
import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// An annotation to draw above or below a range of base text.
///
/// Annotations are handed to `RubyRenderer` directly instead of being
/// attached to the `Text` with `customAttribute(_:)`: custom attributes travel
/// with copied text and make the system fail to write the pasteboard, which
/// breaks Copy for the whole selection.
struct RubyAnnotation {
    /// Distinguishes adjacent annotations.
    let id: Int
    let text: String
    /// UTF-16 offsets of the base text within its paragraph, matching the
    /// paragraph-relative `Text.Layout.Run.characterIndices`.
    let range: Range<Int>
    /// Number of characters in the base text, used to split the annotation
    /// if the base wraps across lines.
    let baseCount: Int
    /// The color of the word it annotates, from `rubyWordColors(_:in:)`.
    var color: Color? = nil
    /// The annotation font in the weight of the word it annotates, from
    /// `rubyWordWeights(_:)`.
    var font: Font? = nil
    /// How visible it is under the furigana filter, from 0 to 1.
    var opacity: CGFloat = 1
    /// Horizontal scale it's drawn at; below 1 for long readings over
    /// numbers in digits.
    var scale: CGFloat = 1
}

/// A word drawn with a colored background.
struct RubyColoredRange {
    /// UTF-16 offsets within the paragraph.
    let range: Range<Int>
    let color: Color
}

/// A word drawn with a line under it.
struct RubyUnderlinedRange {
    /// UTF-16 offsets within the paragraph.
    let range: Range<Int>
    /// The word's own color, if it's colored.
    let color: Color?
    /// How its line is drawn.
    let pattern: RubyUnderlinePattern
}

/// A word set in its own weight.
struct RubyWeightedRange: Hashable {
    /// UTF-16 offsets in the text.
    let range: Range<Int>
    let weight: Font.Weight
}

/// Space added to a range of base text to make room for annotations and
/// word spacing.
struct RubyTrackedRange {
    /// UTF-16 offsets within the paragraph.
    let range: Range<Int>
    /// Space after each glyph, which isn't part of its box.
    let tracking: CGFloat
    /// How far each glyph is drawn to the right of where the layout puts
    /// it, so space can sit before a word as well as after it.
    var shift: CGFloat = 0
}

/// Everything the renderer needs for one paragraph, sorted by range.
struct RubyParagraph {
    var tracked: [RubyTrackedRange] = []
    var furigana: [RubyAnnotation] = []
    /// Drawn above the text or below it, depending on the style.
    var romaji: [RubyAnnotation] = []
    /// Romaji under each kana, drawn below the text.
    var kanaRomaji: [RubyAnnotation] = []
    var backgrounds: [RubyColoredRange] = []
    var underlines: [RubyUnderlinedRange] = []
    /// Blanks to fill, drawn as empty boxes in place of their words.
    var blanks: [Range<Int>] = []
}

/// The word a `RubyReader` is speaking, and how far along it is.
struct RubyEmphasisState {
    let options: RubyEmphasis
    let paragraph: Int
    /// UTF-16 offsets within the paragraph.
    let range: Range<Int>
    /// Eases from 0 to 1 just after the word starts, for grow and highlight.
    let appear: CGFloat
    /// Estimated fraction of the word spoken so far, for karaoke.
    let progress: CGFloat
}

/// Size relationships between base text and its annotations, derived from
/// the font in the environment.
struct RubyMetrics {
    static let annotationScale: CGFloat = 0.5

    /// Annotations use the base font scaled down, so they keep its family and weight.
    let annotationFont: Font
    /// The base font as the text sets it; see `phraseBreaking(_:)`.
    let textFont: Font
    private let base: Font.Resolved
    private let annotation: Font.Resolved
    /// The font and context these were derived from, for other weights.
    private let font: Font
    private let context: Font.Context

    init(font: Font, in context: Font.Context) {
        self.font = font
        self.context = context
        annotationFont = font.scaled(by: Self.annotationScale)
        base = font.resolve(in: context)
        annotation = annotationFont.resolve(in: context)
        textFont = Font(Self.phraseBreaking(base.ctFont))
    }

    /// The same metrics for text in `weight`, or these for `nil`.
    func weighted(_ weight: Font.Weight?) -> RubyMetrics {
        weight.map { RubyMetrics(font: font.weight($0), in: context) } ?? self
    }

    private static let phraseBreakingFonts = NSCache<CTFont, CTFont>()

    /// The font descriptor attribute holding a font's text style. AppKit
    /// fonts have the same attribute, but only UIKit names it.
    private static let textStyleAttribute: CFString = {
        #if canImport(UIKit)
        UIFontDescriptor.AttributeName.textStyle.rawValue as CFString
        #else
        "NSCTFontUIUsageAttribute" as CFString
        #endif
    }()

    /// The same font without its text style.
    ///
    /// Japanese text breaks lines between phrases (東京へ|行きたい) only in
    /// fonts without a text style; in a text-style font such as `.body` it
    /// breaks between almost any two characters (東京|へ).
    /// The font keeps its face, size, weight, and design, so the text looks
    /// the same, and is resolved again whenever Dynamic Type changes.
    static func phraseBreaking(_ font: CTFont) -> CTFont {
        if let cached = phraseBreakingFonts.object(forKey: font) { return cached }
        var attributes = CTFontDescriptorCopyAttributes(CTFontCopyFontDescriptor(font)) as? [CFString: Any] ?? [:]
        guard attributes.removeValue(forKey: textStyleAttribute) != nil else { return font }
        // The traits keep the design (rounded, serif); the variation keeps
        // the exact weight, since an emphasized style reports bold but
        // draws semibold.
        var traits = CTFontCopyTraits(font) as? [CFString: Any] ?? [:]
        traits.removeValue(forKey: kCTFontSymbolicTrait)
        attributes[kCTFontTraitsAttribute] = traits
        if let variation = CTFontCopyVariation(font) { attributes[kCTFontVariationAttribute] = variation }
        let result = CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), CTFontGetSize(font), nil
        )
        phraseBreakingFonts.setObject(result, forKey: font)
        return result
    }

    /// Identifies the resolved fonts, for caching measurements.
    var cacheKey: String {
        "\(CTFontCopyPostScriptName(base.ctFont)) \(base.pointSize) \(CTFontCopyPostScriptName(annotation.ctFont)) \(annotation.pointSize)"
    }

    /// Point size of the base font.
    var fontSize: CGFloat { base.pointSize }
    /// Space between the base glyphs and an annotation.
    var gap: CGFloat { base.pointSize * 0.06 }
    /// Vertical space reserved above or below every line for annotations.
    var reservedHeight: CGFloat { (annotation.pointSize * 1.2 + gap).rounded(.up) }
    /// How thick an underline is, and how wide its dots.
    var underlineThickness: CGFloat { max(1, base.pointSize * 0.08) }
    /// Vertical space reserved below every line for underlines, between
    /// the text and annotations below it.
    var underlineSpace: CGFloat { (gap * 2 + underlineThickness).rounded(.up) }
    /// Minimum horizontal space between neighboring romaji words.
    var romajiSpacing: CGFloat { annotation.pointSize * 0.4 }

    func baseWidth(of string: String) -> CGFloat { Self.width(of: string, font: base.ctFont) }
    func annotationWidth(of string: String) -> CGFloat { Self.width(of: string, font: annotation.ctFont) }

    /// Annotation text as drawn: in the annotation font, or `font` for a
    /// word in its own weight, tagged as Japanese like the base text.
    func annotationText(_ string: String, font: Font? = nil) -> Text {
        var text = AttributedString(string)
        text.languageIdentifier = RubyMetrics.language
        return Text(text).font(font ?? annotationFont)
    }

    /// The language text is set in. Tagging it Japanese selects Japanese
    /// fonts for kanji and kana; untagged, they fall back to a Chinese font
    /// with different glyph shapes and widths.
    static let language = "ja"

    /// Typographic width of `string` set in `font`, as Japanese text.
    private static func width(of string: String, font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTLanguageAttributeName as String): language,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
