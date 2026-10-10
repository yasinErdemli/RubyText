# Analyzers and dictionaries

RubyText doesn't find words itself: an analyzer behind the `RubyAnalyzer`
protocol does. RubyText's own rules for numbers, dates, counters and set
phrases, readings you give, and readings by meaning from a language model
all work on top of whichever analyzer the app sets with `.rubyAnalyzer(_:)`.

## Choosing one

| Analyzer | Size | Reads | Notes |
| --- | --- | --- | --- |
| `RubyMeCabAnalyzer` with IPAdic | about 50 MB | 241 of the 255-word benchmark | The usual choice. Mecab-Swift's `IPADic` product ships it. Unchanged since 2007, so it misses recent words. |
| `RubyMeCabAnalyzer` with UniDic 2.1.2 | about 250 MB | 243; 39 of 50 recent words, against IPAdic's 36 | `unidic-lite` Python package's `dicdir` folder. |
| `RubyMeCabAnalyzer` with UniDic 3.1 | about 770 MB | 242; 42 of 50 recent words | `unidic` Python package. Too large to bundle for most apps. |
| Apple's tokenizer (below) | none | 243 | No dictionary, but no grammar: no word colors by part of speech, no phrase grouping, and some readings lose distinctions (手作り reads てずくり). |
| Your own | — | — | Sudachi, Lindera, a server: anything that gives readings. |

The rules settle most of the benchmark whatever the analyzer; the words left
are those read by meaning, which a language model handles.

## MeCab

```swift
import RubyMeCab

let analyzer = RubyMeCabAnalyzer(dictionary: url)
analyzer.format   // .ipadic or .unidic, read from the folder's dicrc
```

`url` is a folder holding a compiled dictionary: `sys.dic`, `matrix.bin`,
`char.bin`, `unk.dic` and `dicrc`. The initializer tells IPAdic and UniDic
apart, so the same code takes either.

- **IPAdic from Mecab-Swift:** depend on
  `https://github.com/shinjukunian/Mecab-Swift` (from 0.8.0), link its
  `IPADic` product, and pass `IPADic().url`.
- **A dictionary you bundle:** add the folder to the app target as a folder
  reference named, for example, `ipadic.bundle`, and pass
  `Bundle.main.url(forResource: "ipadic", withExtension: "bundle")!`.
- **UniDic:** too large for most app bundles; consider downloading it after
  install and passing its folder once it's on disk.

Loading the dictionary is the expensive part: create one analyzer for the
app and share it (it's `Sendable`, and MeCab calls are serialized inside).
Two analyzers compare equal only if they're the same instance, so a new
instance per view also defeats RubyText's cache. If the dictionary can't be
loaded, the analyzer finds no words and text shows without readings, with
no error: check with `analyzer.segments(in: "東京")`.

Pass the same analyzer to `RubyConverter(analyzer:)`, and to
`RubyReader(analyzer:)` for text no `RubyText` shows.

## Writing an analyzer

```swift
public protocol RubyAnalyzer: Hashable, Sendable {
    /// Segments covering all of `text`, in order; joining their `base`
    /// returns `text`.
    func segments(in text: String) -> [RubySegment]
}
```

Only `base` is required; the more a segment says, the more RubyText can do:

| Property | What it gives |
| --- | --- |
| `reading` | Furigana and romaji: the whole segment's reading, with okurigana (いき for 行き), in hiragana or katakana. Kana needs none. |
| `pronunciation` | Long vowels in romaji: とーきょー gives Tōkyō, おう for 追う gives ou. |
| `word.partOfSpeech` | Word colors by part of speech, and は read as wa. |
| `word.attachesToPrevious` | Reading phrases (文節): spacing, line breaks and read-aloud emphasis keep particles and endings with their word. |
| `word.dictionaryForm` | Vocabulary colors and word details by dictionary form: 生まれる for 生まれた. |
| `word.isProperNoun` | Capitalized names in romaji: Tōkyō, Tanaka. |

A segment with a reading, or with any letters or digits, is a word even if
`word` is `nil`. Leave punctuation as a segment with neither. Readings an
analyzer finds count as the dictionary's, so markup, rules and the model can
correct them.

Requirements that matter:

- **Equal analyzers give equal results.** Results are cached per analyzer.
  A struct with no stored state, or a class compared by identity, is right.
- **`Sendable` and `nonisolated`.** Long text is analyzed off the main
  actor. In an app target whose default isolation is the main actor, as new
  Xcode projects are, declare the type `nonisolated`.
- **Fast.** Text up to 200 UTF-16 code units is analyzed on the main actor
  as it appears, so a sentence should take a millisecond or two. A network
  analyzer is too slow for that.

### Apple's built-in tokenizer

It needs no dictionary. It gives each word's reading as romaji, which this
turns back into hiragana:

```swift
import Foundation
import RubyCore

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
```

### Wrapping another tokenizer

Map its features onto `RubySegment` and leave out what it doesn't know.
`myTokenizer` stands for the tokenizer you wrap:

```swift
nonisolated struct MyTokenizerAnalyzer: RubyAnalyzer {
    func segments(in text: String) -> [RubySegment] {
        myTokenizer.tokenize(text).map { token in
            RubySegment(
                token.surface,
                reading: token.reading,                 // katakana is fine
                pronunciation: token.pronunciation,
                word: RubySegment.Word(
                    partOfSpeech: token.isParticle ? .particle : token.isVerb ? .verb : .noun,
                    dictionaryForm: token.lemma,
                    attachesToPrevious: token.isParticle || token.isSuffix,
                    isProperNoun: token.isProperNoun
                )
            )
        }
    }
}
```

Check it the way RubyText relies on it: the bases join back into the text,
and kanji words have readings.

```swift
let segments = analyzer.segments(in: "東京へ行きたい。")
assert(segments.map(\.base).joined() == "東京へ行きたい。")
```
