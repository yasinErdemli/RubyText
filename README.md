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
  counters and set phrases, and optionally a language model for words whose
  reading depends on their meaning: Apple's on-device model, or any
  provider's. `{base|reading}` markup overrides any of them.
- **Every way to write a reading:** furigana in hiragana, katakana or romaji;
  romaji above or below; inline readings, 東京（とうきょう）; or the whole text
  in hiragana, katakana or romaji. Romaji in Hepburn, Kunrei-shiki,
  Nihon-shiki, passport style, as typed, or for Turkish readers; readings in
  Cyrillic or Hangul; or in a style of your own.
- **For learners:** furigana only above a JLPT level, word colors by part of
  speech, JLPT level or your own vocabulary, space between words or phrases,
  and word details with definitions from JMdict.
- **Read aloud:** synthesized or from a recording, with the phrase being
  spoken emphasized.
- **Accessible:** VoiceOver says readings the way the furigana show them,
  and opens word details. Dynamic Type and Reduce Motion are respected, and
  copying gives the text without its readings.

To try it first, run [RubyText Demo](<RubyText Demo repository URL>). Its Try
tab shows your own text with any settings and gives you the code for them;
Features shows each feature with its code.

## Requirements

iOS 27, macOS 27 or visionOS 27, and Swift 6.2.

## Installation

Add RubyText with Swift Package Manager, in Xcode with File › Add Package
Dependencies, or in `Package.swift`:

```swift
.package(url: "<repository URL>", from: "1.0.0")
```

It has four products; take the ones you need:

| Product | What it does | Needs |
| --- | --- | --- |
| `RubyUI` | `RubyText` and the views around it | `RubyCore` |
| `RubyCore` | Readings as data: markup, rules, conversion, dictionary lookups, with the analyzer you choose | `RubyTransliteration` |
| `RubyMeCab` | An analyzer: MeCab with a dictionary in IPAdic's format | `RubyCore`, [Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift) |
| `RubyTransliteration` | Kana to romaji, hiragana and katakana | Only the standard library |

### Analyzers and dictionaries

RubyText bundles no dictionary, and finds words and readings with whichever
analyzer your app chooses.

**MeCab with IPAdic**, from the `RubyMeCab` product, is the most complete.
The simplest way to get IPAdic is the `IPADic` product of Mecab-Swift,
which RubyMeCab depends on. Set the analyzer once, near the root of your
app:

```swift
import IPADic
import RubyMeCab
import RubyUI   // also imports RubyCore and RubyTransliteration

let analyzer = RubyMeCabAnalyzer(dictionary: IPADic().url)

ContentView()
    .rubyAnalyzer(analyzer)
```

**Any other analyzer** works too: conform to `RubyAnalyzer`, which has one
method that splits text into words with readings. RubyText's rules for
numbers, counters and phrases, and readings by meaning, work on top of it.
The documentation's "Using Any Analyzer" article lists what each part of a
word gives, with an analyzer on Apple's built-in tokenizer: it needs no
dictionary, and reads 225 of the benchmark's 255 words right, against 241
for MeCab with IPAdic.

Without an analyzer, only readings in `{base|reading}` markup show.

**JMdict** gives word details their definitions. Build an SQLite database
from it with [`Tools/build-dictionary.py`](Tools/build-dictionary.py),
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
    .rubyRomanization(.nippon)              // Tôkyô
    .rubyFurigana(.above(.n4))              // none over N5 and N4 kanji
    .foregroundStyle(.primary, .red, .blue) // red furigana, blue romaji
```

`.rubyStyle(.romaji)` alone puts romaji above the text, and
`.rubyFuriganaPosition(.inline)` writes readings in parentheses:
東京（とうきょう）.

SwiftUI's own text modifiers apply as they do to `Text`: `.font`,
`.multilineTextAlignment`, `.lineLimit` and `.truncationMode`, with readings
only over the text shown, and `.textSelection`.

### Writing the text out

```swift
RubyText("今日はコーヒーを飲んだ。")
    .rubyTranscription(.hiragana) // きょうはコーヒーをのんだ。
```

`.hiragana(loanwords: .hiragana)` writes loanwords in hiragana too,
`.katakana` everything in katakana, and `.romaji` with
`.rubyRomanization(.passport)` gives kyo wa kohi o nonda.

`rubyRomanization(_:)` chooses how romaji are written: `.hepburn` by
default, `.kunrei`, `.nippon`, `.passport`, `.wapuro` (as typed: toukyou),
`.turkish` (Şinbun), `.polivanov` (Cyrillic: симбун) or `.hangul` (신분).
Names of people and places start with a capital: Tōkyō. For your own style,
change a built-in table, or conform to `RubyTransliterationStyle` for a
system a table can't express:

```swift
var style = RubyTableStyle.hepburn
style.words["東京"] = "Tokyo"
style.longVowels = .marked(RubyTableStyle.circumflexes)

RubyText(text)
    .rubyStyle(.romaji)
    .rubyRomanization(RubyRomanization(style))
```

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
RubyText(markup: json)   // markup you load at run time
RubyText(comment)        // a String: shown as written
```

Markup is read the way `Text` reads Markdown: in literals, and where you ask
for it with `RubyText(markup:)`. A `String` you pass, such as a comment
someone typed, is shown as written, so it can't add readings.

In code, give readings with string interpolation:

```swift
RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
RubyText("\(unannotated: "無印良品")で本を\(count)冊買った。") // 無印良品 is never annotated
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
String Catalog generates; its translations can use markup.

To show readings from your own data with no analysis, pass segments:

```swift
RubyText(segments: [
    RubySegment("東京", reading: "とうきょう"),
    RubySegment("へ"),
])
```

To have a language model read words like 辛い (からい or つらい) from
context, add `.rubyModelReadings()`. Apple's on-device model answers by
default; pass any FoundationModels `LanguageModel` to use another:

```swift
RubyText(text)
    .rubyModelReadings(model: PrivateCloudComputeLanguageModel()) // Apple's larger model
```

A model from another provider, such as Claude, OpenAI or a local server,
works once it conforms to `LanguageModel`. It must support guided
generation, since RubyText limits its answer to the listed meanings with a
schema. The `Language Models` folder of
[RubyText Demo](<RubyText Demo repository URL>) has complete examples for
Claude and for OpenAI-compatible APIs. Models off the device receive each
sentence they're asked about, and an app you ship shouldn't contain a
provider's API key.

### Word details

```swift
RubyText(text)
    .rubyWordDetails()                 // a popover with the word's details
    .onRubyWordTap { word in save(word) } // or your own action
```

### Reading aloud

```swift
@State private var reader = RubyReader()

RubyText(text)
    .rubyReader(reader)
    .rubyEmphasis([.tint, .grow])
Button("Read Aloud") { reader.speak(text) }
```

The reader reads with the analyzer and spoken readings of the views it's
attached to, so it emphasizes the words they show.

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
fixed rather than an independent test. "With the model" is Apple's
on-device model.

Words whose reading depends on meaning have a benchmark of their own, on
RubyText Demo's Model Benchmark page: 55 sentences with one such word each,
24 pairs of sentences where only the first settles the word in the second,
and a diary with 17 such words. Apple's on-device model reads 71 of the 79
sentences and pairs right, measured on an iPhone 17e. Claude Haiku 5.5,
through RubyText Demo's `ClaudeModel`, reads all 96 words right.

## Licence

The code is under the Apache License 2.0, copyright 2026 Yasin Erdemli; see
[LICENSE](LICENSE). Data and dependencies keep their own licences; see
[NOTICES.md](NOTICES.md).
