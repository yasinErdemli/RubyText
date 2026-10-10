# Using Any Analyzer

Find words and readings with MeCab, Apple's tokenizer, a server, or anything
else.

## Overview

RubyText doesn't find words itself: an analyzer does, behind the
``RubyAnalyzer`` protocol. RubyText includes one, `RubyMeCabAnalyzer` in the
`RubyMeCab` product, for MeCab with a dictionary in IPAdic's format. For any
other, write a type with one method that splits text into ``RubySegment``s,
and set it once, near the root of your app:

```swift
ContentView()
    .rubyAnalyzer(MyAnalyzer())
```

RubyText's rules for numbers, dates, counters and set phrases, and readings
by meaning from a language model, work on top of any analyzer.

### What segments say

Each segment is a piece of the text, and joining their `base` gives the text
back. Only `base` is required; the more a segment says, the more RubyText
can do with it:

| Property | What it gives |
| --- | --- |
| `reading` | Furigana and romaji. The reading of the whole segment, in hiragana or katakana, with its okurigana: いき for 行き. Kana needs none: it's read as written. |
| `pronunciation` | Long vowels in romaji: とーきょー for 東京 gives Tōkyō, おう for 追う gives ou. |
| `word.partOfSpeech` | Word colors by part of speech, and は read as wa. |
| `word.attachesToPrevious` | Reading phrases (文節): spacing, line breaks and read-aloud emphasis keep particles and endings with their word. |
| `word.dictionaryForm` | Vocabulary colors and word details by dictionary form: 生まれる for 生まれた. |
| `word.isProperNoun` | Capitalized names in romaji: Tōkyō, Tanaka. |

A segment with a reading, or with any letters or digits, is a word even if
`word` is `nil`. Leave punctuation as a segment with neither. Readings an
analyzer finds count as the dictionary's, so readings you write in markup,
rules and the language model can correct them.

Analyzers are `Hashable`, so RubyText can cache results for each analyzer:
two that compare equal must return the same segments for the same text. A
class that loads a dictionary usually compares by identity. They're also
`Sendable`, since text is analyzed off the main actor.

### An analyzer with Apple's tokenizer

Apple's tokenizer comes with the system, so it needs no dictionary. It gives
each word's reading as romaji, which this analyzer turns back into hiragana.
It's `nonisolated` because text is analyzed off the main actor, which apps
whose code is isolated to the main actor by default must say:

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

With RubyText's rules, it reads 225 of the 255 words in the reading
benchmark right, against 241 for MeCab with IPAdic. It knows no grammar, so
the features that need it fall back to simpler behavior, and turning romaji
back into kana loses some distinctions: 手作り reads てずくり, not てづくり.

### Other analyzers

Any tokenizer that gives readings fits the same shape: MeCab with another
dictionary, such as UniDic, through the Mecab-Swift package; Sudachi or
Lindera through a Swift wrapper; or a server you send text to. Map its
features to a segment's properties, and leave out what it doesn't know.
