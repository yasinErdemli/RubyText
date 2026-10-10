import Foundation
@testable import RubyCore
import Testing

/// The analyzer in the "Using Any Analyzer" article, kept here so the
/// article's code compiles and works.
nonisolated struct AppleTokenizerAnalyzer: RubyAnalyzer {
    func segments(in text: String) -> [RubySegment] {
        let string = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: string.length),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var segments: [RubySegment] = []
        var position = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Text between words, such as punctuation, has nothing to read.
            if range.location > position {
                segments.append(RubySegment(string.substring(with: NSRange(location: position, length: range.location - position))))
            }
            let word = string.substring(with: NSRange(location: range.location, length: range.length))
            var reading: String?
            if word.contains(where: \.isKanji),
               let romaji = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                let kana = NSMutableString(string: romaji)
                CFStringTransform(kana, nil, kCFStringTransformLatinHiragana, false)
                reading = kana as String
            }
            segments.append(RubySegment(word, reading: reading))
            position = range.location + range.length
        }
        if position < string.length {
            segments.append(RubySegment(string.substring(from: position)))
        }
        return segments
    }
}

/// An analyzer that says only what the text is and how it's read, in
/// katakana, as many analyzers report readings.
private struct ReadingsOnlyAnalyzer: RubyAnalyzer {
    func segments(in text: String) -> [RubySegment] {
        [RubySegment("東京", reading: "トウキョウ"), RubySegment("へ"), RubySegment("。")]
    }
}

struct AnalyzerGuideTests {
    @Test func applesTokenizerGivesReadings() {
        let content = RubyContent.content(for: "今日は東京へ行きたい。", analyzer: AppleTokenizerAnalyzer())
        #expect(content.words.flatMap(\.furigana).map(\.text) == ["きょう", "とうきょう", "い"])
        #expect(content.words.allSatisfy { $0.source == .dictionary })
        // Kana words have romaji too, though the analyzer gave them no reading.
        #expect(content.words.allSatisfy { $0.romaji?.isEmpty == false })
    }

    /// Readings alone are enough for furigana: no grammar, no source, and
    /// katakana are fine. Punctuation doesn't become a word.
    @Test func readingsAloneMakeWords() {
        let content = RubyContent.content(for: "東京へ。", analyzer: ReadingsOnlyAnalyzer())
        #expect(content.words.count == 2)
        #expect(content.words.first?.furigana.map(\.text) == ["とうきょう"])
        #expect(content.words.first?.source == .dictionary)
        #expect(content.words.map(\.romaji) == ["tōkyō", "e"])
    }
}
