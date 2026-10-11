---
name: rubytext
description: Show Japanese text with furigana (readings over kanji) and romaji in SwiftUI with the RubyText Swift package, and set up its analyzer, dictionaries, styles, word details, read-aloud and language-model readings. Use this skill whenever code imports RubyUI, RubyCore, RubyMeCab or RubyTransliteration, or uses RubyText, RubyReader, RubyConverter or modifiers such as rubyStyle; and whenever someone wants furigana, ruby text, 振り仮名, readings above kanji, romaji, kana conversion, JLPT-level furigana, word colors for learners, read-aloud highlighting, or a Japanese reading or study screen in an iOS, macOS or visionOS app, even if they don't name RubyText.
license: Apache-2.0
---

# RubyText

RubyText draws Japanese text with readings above its kanji (furigana), romaji
above or below, or both, and finds the readings on device. `RubyText` is used
like SwiftUI's `Text`, and is configured with environment modifiers, like
`.font`, on it or any view above it.

Requirements: iOS 27, macOS 27 or visionOS 27, and Swift 6.2.
Repository: https://github.com/yasinErdemli/RubyText

When RubyText is already a dependency, its source is in the package
checkout (`SourcePackages/checkouts/RubyText` in Xcode's DerivedData, or
`.build/checkouts/RubyText` for SwiftPM). Read `Sources/` there when you
need an exact signature; the doc comments have examples.

## Setting it up

The step most often missed: **RubyText bundles no dictionary, so without an
analyzer only readings written in `{base|reading}` markup show**, and every
other kanji appears bare. A working setup has the package, an analyzer, and
optionally a dictionary for definitions.

### 1. The package

```swift
.package(url: "https://github.com/yasinErdemli/RubyText", from: "1.0.0")
```

| Product | Use it for |
| --- | --- |
| `RubyUI` | `RubyText`, `RubyReader` and the modifiers. Importing it also imports `RubyCore` and `RubyTransliteration`. |
| `RubyMeCab` | `RubyMeCabAnalyzer`: MeCab with an IPAdic or UniDic dictionary. The analyzer to use unless there's a reason not to. |
| `RubyCore` | Readings as data, without SwiftUI: `RubyConverter`, `RubyString`, `RubyDictionary`, the `RubyAnalyzer` protocol. |
| `RubyTransliteration` | Kana to romaji, and hiragana to katakana, with no dictionary. |

`RubyMeCab` needs the `MeCab` package trait, which is on by default. If the
app won't use it (it only shows readings it already has, or uses another
analyzer), depend on RubyText 1.1.0 or later with `traits: []`, and Swift
Package Manager won't download Mecab-Swift and its dictionaries, about
400 MB per build folder.

### 2. An analyzer, created once, set at the root

The quickest dictionary is IPAdic from the `IPADic` product of Mecab-Swift,
which RubyMeCab already depends on. To link that product, the app declares
the Mecab-Swift package itself: in Xcode, add
`https://github.com/shinjukunian/Mecab-Swift` and link `IPADic`; in
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yasinErdemli/RubyText", from: "1.0.0"),
    .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "RubyUI", package: "RubyText"),
        .product(name: "RubyMeCab", package: "RubyText"),
        .product(name: "IPADic", package: "Mecab-Swift"),
    ]),
]
```

```swift
import IPADic
import RubyMeCab
import RubyUI
import SwiftUI

@main
struct MyApp: App {
    // Loading the dictionary is the expensive part: create one analyzer
    // for the whole app, never in a view's body or initializer.
    let analyzer = RubyMeCabAnalyzer(dictionary: IPADic().url)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .rubyAnalyzer(analyzer)
        }
    }
}
```

For UniDic (more recent words, larger), a dictionary you bundle, Apple's
built-in tokenizer (no dictionary at all), or your own analyzer, read
[references/analyzers.md](references/analyzers.md).

### 3. Optionally, definitions

Word details show reading, part of speech and JLPT level without a
dictionary. For definitions, build an SQLite database from JMdict with
`Tools/build-dictionary.py` in the RubyText repository, bundle it, and set it
like the analyzer:

```swift
ContentView()
    .rubyDictionary(RubyDictionary(url: Bundle.main.url(forResource: "jmdict", withExtension: "sqlite")!))
```

JMdict's licence (CC BY-SA 4.0) asks the app to acknowledge it, for example
in an About screen; `RubyDictionary.credit` is a ready-made line.

## Showing text

```swift
RubyText("{今日|きょう}は日本語を勉強しています。")
    .font(.title)
    .textSelection(.enabled)
    .rubyStyle([.furigana, .romaji])   // furigana above, romaji below
```

Markup is read the way `Text` reads Markdown: only where the code opts in.
This is deliberate, so text people type can never inject readings.

```swift
RubyText("{宇宙|そら}を見上げた。")  // a literal: markup read
RubyText(markup: json)            // markup loaded at run time: read
RubyText(comment)                 // a String value: shown as written, braces and all
RubyText(verbatim: "{a|b}")       // shown as written
RubyText(.welcome)                // a LocalizedStringResource: read, so translations can use markup
RubyText(segments: segments)      // [RubySegment]: no analysis, only the readings you give
```

So if braces show on screen, the text was a `String` value: pass it with
`RubyText(markup:)`. And text from people using the app should be passed as a
plain `String`, never as `markup:`.

In code, give readings with string interpolation:

```swift
RubyText("\("今日", reading: "きょう")は\(user.name)さんと話した。")
RubyText("\(unannotated: "無印良品")で本を\(count)冊買った。") // 無印良品 is never annotated
```

- `\(base, reading:)` takes an optional reading; `nil` falls back to analysis.
- Interpolated strings and numbers are analyzed with the words around them,
  so `\(3)冊` reads さんさつ. Markup inside them shows as written.
- `PersonNameComponents` read with their `phoneticRepresentation`, and any
  type can conform to `RubyStringConvertible` to supply its own readings.
- Unlike `Text`, a literal isn't localized. For localized text pass a
  `LocalizedStringResource`, such as the symbols a String Catalog generates.

Readings in markup can be hiragana or katakana; katakana is kept as written
(`{本気|マジ}`).

## Modifiers

All are environment modifiers: set them on a `RubyText` or any container,
and changes animate.

| Modifier | Values | Default |
| --- | --- | --- |
| `rubyAnalyzer(_:)` | `RubyMeCabAnalyzer` or any `RubyAnalyzer` | none: markup only |
| `rubyStyle(_:)` | `.furigana`, `.romaji` (above), `[.furigana, .romaji]`, `[]` | `.furigana` |
| `rubyFurigana(_:)` | `.all`, `.above(.n4)`, `.above(.n4, except: known)`, `.except(known)` | `.all` |
| `rubyFuriganaScript(_:)` | `.hiragana`, `.katakana`, `.romaji` | `.hiragana` |
| `rubyFuriganaPosition(_:)` | `.above`, `.inline`: 東京（とうきょう） | `.above` |
| `rubyTranscription(_:)` | whole text as `.hiragana`, `.hiragana(loanwords: .hiragana)`, `.katakana`, `.romaji`; `nil` as written | `nil` |
| `rubyRomanization(_:)` | `.hepburn`, `.kunrei`, `.nippon`, `.passport`, `.wapuro`, `.turkish`, `.polivanov` (Cyrillic), `.hangul`, or `RubyRomanization(style)` | `.hepburn` |
| `rubySpacing(_:)` | `.none`, `.words`, `.phrases`, `.words(width:)`, `.phrases(width:)` | `.none` |
| `rubyLineBreaking(_:)` | `.phrases`, `.anywhere` | `.phrases` |
| `rubyDigitReadingsHidden(_:)` | hide readings over 2026年, 3日 | `false` |
| `rubyWordColors(_:in:)` | `.partOfSpeech`, `.alternating`, `.words([…])`, `.jlpt`, `.jlpt(above: .n4)`, `.readingSources`; `in: .text` or `.background` | none |
| `rubyWordDetails(_:)` | popover with reading, dictionary form, part of speech, JLPT level, definitions | off |
| `onRubyWordTap(perform:)` | your own action with a `RubyWordInfo` | none |
| `rubyDictionary(_:)` | `RubyDictionary` for definitions | none |
| `rubyReader(_:)`, `rubyEmphasis(_:)` | read-aloud highlighting: `.tint`, `.highlight`, `.grow`, `.karaoke` | `[.tint, .grow]` |
| `rubySpokenReadings(_:)` | what VoiceOver says: `.corrections`, `.all`, `[]` | `.corrections` |
| `rubyModelReadings(_:updates:model:)` | a language model for words read by meaning | off |

SwiftUI's own text modifiers work as on `Text`: `.font`,
`.multilineTextAlignment`, `.lineLimit`, `.truncationMode` and
`.textSelection`. Furigana use the secondary foreground style and romaji the
tertiary one, so `.foregroundStyle(.primary, .red, .blue)` gives red
furigana and blue romaji. The spoken word uses `.tint`.

Signatures and every option: [references/api.md](references/api.md).

## Recipes

A study screen: furigana only on kanji beyond N4, romaji below, words colored
by grammar, phrases spaced, a tap for details, and reading aloud.

```swift
struct PassageView: View {
    let passage: String
    @State private var reader = RubyReader()

    var body: some View {
        ScrollView {
            RubyText(passage)
                .font(.title2)
                .textSelection(.enabled)
                .padding()
        }
        .rubyStyle([.furigana, .romaji])
        .rubyFurigana(.above(.n4))
        .rubyWordColors(.partOfSpeech)
        .rubySpacing(.phrases)
        .rubyWordDetails()
        .rubyReader(reader)
        .toolbar {
            Button(reader.isSpeaking ? "Stop" : "Read Aloud", systemImage: "speaker.wave.2") {
                if reader.isSpeaking {
                    reader.stop()
                } else {
                    reader.speak(passage)
                }
            }
        }
    }
}
```

The reader takes the analyzer of the views it's attached to, so its
emphasis lines up with the words they show. A recording works too:
`try await reader.play(narration: url, for: passage)` aligns it with
on-device speech recognition.

A vocabulary list that saves the tapped word:

```swift
RubyText(sentence)
    .rubyWordColors(.words(lesson.words), in: .background)
    .onRubyWordTap { word in
        studyList.add(word.dictionaryForm ?? word.text, reading: word.reading)
    }
```

Plain strings, for search, sharing or notifications, with `RubyConverter`:

```swift
let converter = RubyConverter(analyzer: analyzer)
converter.convert("今日はコーヒーを飲んだ。", to: .hiragana) // きょうはコーヒーをのんだ。
converter.convert("今日はコーヒーを飲んだ。", to: .romaji)   // kyō wa kōhī o nonda.
converter.annotate("東京へ行きたい。", with: .hiragana)     // 東京（とうきょう）へ行（い）きたい。
```

Kana alone needs no analyzer: `RubyKana.hiragana("トウキョウ")` is とうきょう, and
`RubyRomanization.hepburn.transliterate("とうきょう")` is tōkyō.

Words whose reading depends on meaning, such as 辛い (からい for spicy,
つらい for hard), are read by a language model with `.rubyModelReadings()`:
Apple's on-device model by default, or any FoundationModels `LanguageModel`,
including other providers. See
[references/language-models.md](references/language-models.md).

## Things that go wrong

- **Kanji show without readings.** No analyzer reached the view, or the
  dictionary didn't load (the analyzer then finds no words, silently). Check
  that `.rubyAnalyzer(_:)` is above the view, including in previews, and
  that `analyzer.segments(in: "東京")` returns a reading.
- **A wrong reading.** Don't change the analyzer for one word; give the
  reading with markup, `{寿司|すし}`, or `\(base, reading:)`. Readings you give
  always win over rules, the model and the dictionary.
- **Braces on screen.** The text was a `String` value; pass it with
  `RubyText(markup:)` if it's markup you trust.
- **Readings appear a moment late.** Text over 200 UTF-16 code units shows
  at once and is analyzed in the background, its readings fading in. UI
  tests and snapshots should wait for them.
- **A slow screen.** An analyzer created per view loads its dictionary each
  time. Create one and share it.
- **Concurrency errors in a custom analyzer.** `RubyAnalyzer` is `Hashable`
  and `Sendable`, and text is analyzed off the main actor, so in an app
  whose code is isolated to the main actor by default, mark the type
  `nonisolated`.
- **The app is stopped when the model is asked.**
  `PrivateCloudComputeLanguageModel()` needs the
  `com.apple.developer.private-cloud-compute` entitlement. Never work around
  it, and never put a provider's API key in an app you ship.
- **Building ruby by hand.** Don't stack `Text` views or attributed strings
  to fake furigana: alignment, line breaking, selection, VoiceOver and
  Dynamic Type are what `RubyText` handles. For readings you already have,
  use markup or `RubyText(segments:)`.

## References

- [references/api.md](references/api.md): every public type and modifier,
  with signatures, options and defaults.
- [references/analyzers.md](references/analyzers.md): choosing and bundling
  dictionaries, UniDic, writing an analyzer, Apple's tokenizer.
- [references/language-models.md](references/language-models.md): readings
  by meaning with Apple's models or another provider, such as Claude or an
  OpenAI-compatible API.
