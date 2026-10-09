# RubyText

Furigana and romaji for SwiftUI.

![振り仮名をSwiftUIで。 with furigana above and romaji below](Images/furigana-and-romaji.png)

RubyText shows Japanese text with readings above its kanji, romaji above or
below, or both, and finds the readings on device. Use it like `Text`:

```swift
RubyText("{今日|きょう}は日本語を勉強しています。")
    .font(.title)
    .rubyStyle([.furigana, .romaji])
```

- **Readings found on device:** MeCab with IPAdic, rules for numbers, dates,
  counters and set phrases, and optionally Apple's on-device model for words
  whose reading depends on their meaning. `{base|reading}` markup overrides
  any of them.
- **Every way to write a reading:** furigana in hiragana, katakana or romaji;
  romaji above or below; inline readings, 東京（とうきょう）; or the whole text
  in hiragana, katakana or romaji. Romaji in Hepburn, Nihon-shiki or passport
  style.
- **For learners:** furigana only above a JLPT level, word colors by part of
  speech, JLPT level or your own vocabulary, space between words or phrases,
  and word details with definitions from JMdict.
- **Read aloud:** synthesized or from a recording, with the phrase being
  spoken emphasized.
- **Accessible:** VoiceOver says readings the way the furigana show them,
  and opens word details. Dynamic Type and Reduce Motion are respected, and
  copying gives the text without its readings.

## Requirements

iOS 27, macOS 27 or visionOS 27, and Swift 6.2.

## Installation

Add RubyText with Swift Package Manager, in Xcode with File › Add Package
Dependencies, or in `Package.swift`:

```swift
.package(url: "<repository URL>", from: "1.0.0")
```

It has three products; take the one you need:

| Product | What it does | Needs |
| --- | --- | --- |
| `RubyUI` | `RubyText` and the views around it | `RubyCore` |
| `RubyCore` | Readings as data: analysis, markup, conversion, dictionary lookups | `RubyTransliteration`, [Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift) |
| `RubyTransliteration` | Kana to romaji, hiragana and katakana | Only the standard library |

### Dictionaries

RubyText bundles no dictionary, so your app chooses its own.

**IPAdic** finds words and readings. The simplest way to get it is the
`IPADic` product of Mecab-Swift, which RubyText already depends on. Set the
analyzer once, near the root of your app:

```swift
import IPADic
import RubyCore
import RubyUI

let analyzer = RubyMeCabAnalyzer(dictionary: IPADic().url)

ContentView()
    .rubyAnalyzer(analyzer)
```

Without an analyzer, only readings in `{base|reading}` markup show.

**JMdict** gives word details their definitions. Build an SQLite database
from it with [`Tools/build-dictionary.py`](../Tools/build-dictionary.py),
bundle it, and set it like the analyzer:

```swift
ContentView()
    .rubyDictionary(RubyDictionary(url: Bundle.main.url(forResource: "jmdict", withExtension: "sqlite")!))
```

JMdict's licence asks your app to acknowledge it, for example in an About
screen; see [NOTICES.md](NOTICES.md).

## Usage

### Styles

Annotations are set through the environment, like fonts, on a `RubyText` or
any view above it. Changes animate.

```swift
RubyText("東京へ行きたい。")
    .rubyStyle([.furigana, .romaji])        // furigana above, romaji below
    .rubyFuriganaScript(.katakana)          // トウキョウ over 東京
    .rubyRomanization(.nippon)              // tôkyô
    .rubyFurigana(.above(.n4))              // none over N5 and N4 kanji
    .foregroundStyle(.primary, .red, .blue) // red furigana, blue romaji
```

`.rubyStyle(.romaji)` alone puts romaji above the text, and
`.rubyFuriganaPosition(.inline)` writes readings in parentheses:
東京（とうきょう）.

### Writing the text out

```swift
RubyText("今日はコーヒーを飲んだ。")
    .rubyTranscription(.hiragana) // きょうはコーヒーをのんだ。
```

`.hiragana(loanwords: .hiragana)` writes loanwords in hiragana too,
`.katakana` everything in katakana, and `.romaji(system: .passport)` gives
kyo wa kohi o nonda.

For plain strings, such as for search or sharing, use `RubyConverter`:

```swift
let converter = RubyConverter(analyzer: analyzer)
converter.convert("感じ取れたら手を繋ごう", to: .romaji)      // kanjitoretara te o tsunagō
converter.annotate("東京へ行きたい。", with: .hiragana)    // 東京（とうきょう）へ行（い）きたい。
```

### Your own readings

Markup sets a reading where the automatic one is wrong, or for names:

```swift
RubyText("{宇宙|そら}を見上げた。")
```

In code, give readings with string interpolation:

```swift
RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
RubyText("\(verbatim: "無印良品")で本を\(count)冊買った。") // 無印良品 is never annotated
```

`\(base, reading:)` takes an optional reading, so a missing one falls back to
analysis. Strings and numbers you interpolate are read with the words around
them, so `\(3)冊` reads さんさつ, and markup in them shows as written, so text
people type can't add readings. `PersonNameComponents` read with their
phonetic names, and your own types can too by conforming to
`RubyStringConvertible`:

```swift
struct User: RubyStringConvertible {
    var familyName = "田中", givenName = "花子"
    var familyKana: String? = "たなか", givenKana: String? = "はなこ"

    var rubyString: RubyString {
        "\(familyName, reading: familyKana)\(givenName, reading: givenKana)"
    }
}
```

Unlike `Text`, a literal isn't localized. For localized text, pass a
`LocalizedStringResource`, such as `RubyText(.welcome)` with the symbols your
String Catalog generates, or `String(localized:)`. Both can use markup.

To show readings from your own data with no analysis, pass segments:

```swift
RubyText(segments: [
    RubySegment("東京", reading: "とうきょう"),
    RubySegment("へ"),
])
```

To have Apple's on-device model read words like 辛い (からい or つらい) from
context, add `.rubyModelReadings()`.

### Word details

```swift
RubyText(text)
    .rubyWordDetails()                 // a popover with the word's details
    .onRubyWordTap { word in save(word) } // or your own action
```

### Reading aloud

```swift
@State private var reader = RubyReader(analyzer: analyzer)

RubyText(text)
    .rubyReader(reader)
    .rubyEmphasis([.tint, .grow])
Button("Read Aloud") { reader.speak(text) }
```

### VoiceOver

VoiceOver reads the text once, without the annotations, and says the
readings a voice would likely get wrong the way the furigana show them:
yours, and those from rules and the model. Pass `.all` to
`rubySpokenReadings(_:)` to have it say every reading, or `[]` for none.
Braille displays show the text as written.

## Accuracy

The benchmark is 255 words that are easy to read wrong, each in a sentence
that makes its reading clear: numbers and dates, counters, words read as a
whole, words whose reading depends on meaning, phrases, names, and everyday
words as a control. It runs with the tests, in
[`ReadingBenchmark.swift`](Tests/RubyCoreTests/ReadingBenchmark.swift).

| Kind | Words | RubyText | kuroshiro |
| --- | --- | --- | --- |
| Numbers and dates | 29 | 29 | 3 |
| Counters | 22 | 22 | 8 |
| Read as a whole (今日, 大人) | 45 | 45 | 45 |
| Reading depends on meaning (辛い, 人気) | 34 | 20, or 33 with the model | 19 |
| Phrases and compounds (一日中, 本棚) | 62 | 62 | 46 |
| Names | 21 | 21 | 21 |
| Everyday words | 42 | 42 | 42 |
| **All** | **255** | **241, or 254 with the model** | **184** |

kuroshiro is the JavaScript library for furigana, measured at version 1.2.1
with its Kuromoji analyzer, which also uses IPAdic. RubyText's rules were
written against this benchmark, so treat the score as a measure of what's
fixed rather than an independent test.

## Licence

The code is under the MIT License; see [LICENSE](LICENSE). Data and
dependencies keep their own licences; see [NOTICES.md](NOTICES.md).
