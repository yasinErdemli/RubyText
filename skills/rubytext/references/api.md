# RubyText API reference

Every public type and modifier, by product, with options and defaults. The
doc comments in `Sources/` have more examples.

## Contents

- [RubyUI](#rubyui): `RubyText`, modifiers, `RubyReader`, word details
- [RubyCore](#rubycore): `RubyString`, `RubySegment`, `RubyConverter`,
  `RubyDictionary`, `RubyWordInfo`, analyzers, model readings
- [RubyMeCab](#rubymecab): `RubyMeCabAnalyzer`
- [RubyTransliteration](#rubytransliteration): `RubyRomanization`,
  `RubyTableStyle`, `RubyKana`

## RubyUI

`import RubyUI` also imports RubyCore and RubyTransliteration.

### RubyText

```swift
RubyText(_ string: RubyString)                   // literals and interpolation; markup read
RubyText(_ resource: LocalizedStringResource)    // localized; markup in translations read
RubyText<S: StringProtocol>(_ content: S)        // a String value, shown as written
RubyText(verbatim content: String)               // shown as written, even a literal
RubyText(markup: String)                         // {base|reading} markup loaded at run time
RubyText(segments: [RubySegment])                // your own readings, no analysis
```

Short text, up to 200 UTF-16 code units, is analyzed as it appears. Longer
text shows at once with the readings its markup gives and is analyzed off
the main actor, its readings fading in. Selection and copy give the text
without its readings, unless the readings are part of the text
(`.inline`, or a transcription).

### Modifiers on View

| Modifier | Notes |
| --- | --- |
| `rubyAnalyzer(_ analyzer: some RubyAnalyzer)` | Set once, near the root. |
| `rubyStyle(_ style: RubyStyle = .furigana)` | `RubyStyle` is an `OptionSet`: `.furigana`, `.romaji`. Either alone sits above the text; together, furigana above and romaji below. `[]` is plain text. |
| `rubyFurigana(_ filter: RubyFuriganaFilter)` | `.all`; `.above(_ level: RubyJLPTLevel, except knownKanji: Set<Character> = [])` hides readings of kanji at or below the level; `.except(_ knownKanji: some Sequence<Character>)`. A reading spanning several kanji shows if any is unknown. Add `.showing(wordIDs: some Sequence<String>)` to show every reading of chosen words, by their segments' `wordID`, whatever their kanji. |
| `rubyFuriganaScript(_ script: RubyScript)` | `.hiragana` (default; katakana you write in markup is kept), `.katakana`, `.romaji`. |
| `rubyFuriganaPosition(_ position: RubyFuriganaPosition)` | `.above`, `.inline`: 東京（とうきょう）へ行（い）きたい。 Inline readings are part of the text, so they copy with it; romaji, if shown, move above. |
| `rubyTranscription(_ transcription: RubyScript?)` | Writes the whole text out: `.hiragana` (loanwords stay katakana), `.hiragana(loanwords: .hiragana)`, `.katakana`, `.romaji`. `nil`, the default, writes it as it is. Copy gives the transcribed text. |
| `rubyRomanization(_ system: RubyRomanization)` | Applies wherever romaji show: annotations, furigana, inline, transcriptions. See [RubyTransliteration](#rubytransliteration). |
| `rubySpacing(_ spacing: RubySpacing)` | `.none` (default), `.words`, `.phrases` (文節, as children's books), `.words(width:)`, `.phrases(width:)`, width as a fraction of the font size, 0.5 by default. Drawn, not inserted, except in transcriptions, where it's real ideographic space. |
| `rubyLineBreaking(_ lineBreaking: RubyLineBreaking)` | `.phrases` (default: words stay with their particles), `.anywhere` (between characters, never leaving a lone kana on the last line). Either way, no line starts with 。, 」, ー or a small kana: a paragraph whose phrase is wider than the line, as in large text, breaks between characters instead. |
| `rubyDigitReadingsHidden(_ hidden: Bool = true)` | Hides readings over numbers in digits (2026年, 3日); kanji numbers keep theirs. |
| `rubyWordColors(_ colors: RubyWordColors?, in placement: RubyWordColorPlacement = .text)` | Call once for `.text` and once for `.background` to combine; `nil` removes. A colored word's annotations take its color. |
| `rubyWordWeights(_ weights: RubyWordWeights?)` | Sets chosen words in their own weight, such as bold for a grammar point's form; combines with `rubyWordColors`. `.words([String: Font.Weight])`, `.words(_ words: some Sequence<String>, weight: Font.Weight = .bold)`, matched as `RubyWordColors.words` matches; `.wordIDs([String: Font.Weight])`, `.wordIDs(_ ids: some Sequence<String>, weight: Font.Weight = .bold)`, by segments' `wordID`. A word's annotations take its weight; `nil` removes. |
| `rubyWordDetails(_ isEnabled: Bool = true)` | Tap a word for a popover: reading, dictionary form, part of speech, JLPT level, kanji, definitions if a dictionary is set, and buttons to hear it and look it up. VoiceOver reaches it as an accessibility action. |
| `onRubyWordTap(perform action: @escaping (RubyWordInfo) -> Void)` | Your own action instead. |
| `rubyDictionary(_ dictionary: RubyDictionary?)` | Definitions for word details. |
| `rubyReader(_ reader: RubyReader?)` | Emphasizes the phrase a reader is speaking. |
| `rubyEmphasis(_ emphasis: RubyEmphasis)` | `OptionSet`: `.tint`, `.highlight` (uses `backgroundStyle` if set), `.grow`, `.karaoke`. Default `[.tint, .grow]`. |
| `rubySpokenReadings(_ readings: RubySpokenReadings)` | Readings VoiceOver and `RubyReader` say in place of the text: `.corrections` (default: `[.manual, .rule, .model]`), `.all`, or `[]`. Braille shows the text as written. |
| `rubyModelReadings(_ isEnabled: Bool = true, updates: RubyModelReadingUpdates = .allAtOnce, model: any LanguageModel = SystemLanguageModel.default)` | Readings by meaning; `updates: .asAnswered` changes each as it's answered. See [language-models.md](language-models.md). |

### RubyWordColors

| Coloring | What it colors |
| --- | --- |
| `.partOfSpeech`, `.partOfSpeech([RubyPartOfSpeech: Color])` | By grammar: nouns blue, verbs red, adjectives green, particles orange… Roles without a color stay plain. |
| `.alternating`, `.alternating([Color])` | Alternates from word to word, to show word boundaries. |
| `.words([String: Color])`, `.words(_ words: some Sequence<String>, color: Color = .orange)` | Chosen words, matched as written, by dictionary form in any conjugation (生まれる matches 生まれた), or as a run of words (見当がつく). |
| `.wordIDs([String: Color])`, `.wordIDs(_ ids: some Sequence<String>, color: Color = .orange)` | Words by their segments' `wordID`: exactly those words, not others written the same. |
| `.jlpt`, `.jlpt(above: RubyJLPTLevel? = nil, vocabulary: [String: RubyJLPTLevel] = [:])`, `.jlpt([RubyJLPTLevel: Color], vocabulary:)` | By JLPT level, green N5 to red N1. A word's level is its hardest kanji's; `vocabulary` overrides it from your own lists. |
| `.readingSources`, `.readingSources([RubyReadingSource: Color])` | Where each reading came from: yours purple, rules orange, the model green. For checking readings. |

### RubyReader

An `@Observable` class; keep it in `@State`.

```swift
RubyReader()                          // takes its analyzer from the views it's attached to
RubyReader(analyzer: some RubyAnalyzer) // for text no RubyText shows

func speak(_ string: RubyString)               // literals: markup read
func speak(_ text: some StringProtocol)        // String values: as written
func play(narration url: URL, for string: RubyString) async throws
func play(narration url: URL, for text: some StringProtocol) async throws
func play(narration url: URL, for segments: [RubySegment], phraseStarts: [TimeInterval], end: TimeInterval? = nil) async throws
func pause()
func resume()
func stop()

var rate: Float                       // 0.5 to 2, default 1
var voiceIdentifier: String?          // nil: the best Japanese voice installed
var spokenReadings: RubySpokenReadings
static var japaneseVoices: [AVSpeechSynthesisVoice]  // best quality first
private(set) var isSpeaking, isPaused, isPreparing: Bool
private(set) var text: String?
```

It emphasizes reading phrases (吾輩は), since voices say particles with their
word. A recording is aligned with on-device speech recognition the first
time; `swift run align-narration recording.m4a`, run in the RubyText
repository, precomputes `recording.segments.json` to ship next to it. With
timings you already have, play segments with `phraseStarts`, one per phrase
in order: the phrases `rubySpacing(.phrases)` spaces apart, where a segment
doesn't attach to the one before it, also split at punctuation, which isn't
timed. No speech recognition runs.

### RubyWordDetailView

`RubyWordDetailView(word: RubyWordInfo, dictionary: RubyDictionary? = nil)`:
the card `rubyWordDetails()` shows, to present your own way, for example
from `onRubyWordTap` in a sheet.

## RubyCore

### RubyString

`ExpressibleByStringInterpolation`, so literals become one.

```swift
"\(base, reading: String?)"     // a reading you give, or nil for analysis
"\(text)"                       // a string, analyzed with the words around it; markup in it shown as written
"\(number)"                     // a number, read with its counter: \(3)冊 is さんさつ
"\(unannotated: text)"          // never annotated
"\(value)"                      // any RubyStringConvertible, such as PersonNameComponents

RubyString(markup: String)
RubyString(unannotated: String)
var plainText: String           // without readings or markup
static func + (RubyString, RubyString) -> RubyString
```

`protocol RubyStringConvertible { var rubyString: RubyString { get } }`
lets your types supply readings; it doesn't require `Sendable`.
`PersonNameComponents` conforms, reading with `phoneticRepresentation`, and
`rubyString(readings: .katakana)` writes them in katakana.

### RubySegment

```swift
RubySegment(
    _ base: String,
    reading: String? = nil,          // hiragana or katakana, for the whole segment with okurigana
    pronunciation: String? = nil,    // とーきょー: long vowels in romaji
    word: RubySegment.Word? = nil,
    source: RubyReadingSource = .manual,
    wordID: String? = nil            // your ID for its word: consecutive segments with one ID are one word
)

RubySegment.Word(
    partOfSpeech: RubyPartOfSpeech? = nil,
    dictionaryForm: String? = nil,
    attachesToPrevious: Bool? = nil, // particles and endings: keeps phrases together
    isProperNoun: Bool = false       // capitalized in romaji
)
```

Joining every `base` must give the text back. A word in pieces, such as
食|べ|物 with a reading over each kanji, is one word for taps, VoiceOver,
colors and phrases when its segments share a `wordID`; it takes its grammar
from its first segment. Words next to each other need different IDs. In
`RubyText(segments:)`, `attachesToPrevious: false` always starts a phrase,
even a kanji word after an all-kanji one (今日｜何を), which in an analyzer's
segments continues a compound; `nil` lets RubyText decide. Kana segments
without a reading are read as written. `RubyReadingSource`:
`.manual`, `.rule`, `.model`, `.dictionary`, in priority order.
`RubyPartOfSpeech`: `.noun`, `.verb`, `.adjective`, `.adverb`, `.particle`,
`.auxiliary`, `.adnominal`, `.conjunction`, `.prefix`, `.interjection`,
`.other`.

### RubyAnalyzer

```swift
public protocol RubyAnalyzer: Hashable, Sendable {
    func segments(in text: String) -> [RubySegment]
}
```

See [analyzers.md](analyzers.md).

### RubyConverter

```swift
RubyConverter(analyzer: some RubyAnalyzer)
RubyConverter()                 // markup readings only

func convert(_ string: RubyString, to script: RubyScript, romanization: RubyRomanization = .hepburn) -> String
func annotate(_ string: RubyString, with script: RubyScript, romanization: RubyRomanization = .hepburn,
              parentheses: (open: String, close: String) = ("（", "）")) -> String
```

Each also takes `some StringProtocol`, read as written. Romaji output puts
spaces between words and makes punctuation Latin.

### RubyScript

`.hiragana`, `.hiragana(loanwords: RubyScript.Kana)` (`.hiragana` or
`.katakana`), `.katakana`, `.romaji`; `isRomaji`.

### RubyWordInfo

What a tap handler receives: `text` (生まれた), `reading` (うまれた),
`romaji`, `dictionaryForm` (生まれる, if different), `partOfSpeech`,
`jlptLevel`, `kanji: [Kanji]` (each `character` and `level`), `source`,
`wordID` (its segments' ID, if you gave one), and `range`, its UTF-16 range
in the text without markup. `Identifiable` by range.

### RubyDictionary

```swift
RubyDictionary(url: URL)        // failable: nil if the SQLite file can't be opened
func entries(for word: RubyWordInfo, limit: Int = 3) -> [Entry]
static let credit: String        // the JMdict acknowledgment
```

`Entry`: `spellings`, `readings`, `isCommon`, `isUsuallyKana`, `senses`
(each `partsOfSpeech`, `partOfSpeechCodes`, `glosses`). The best match for
the reading shown comes first, so 人気 read ひとけ finds "human presence".

### RubyJLPTLevel

`.n5`, `.n4`, `.n3`, `.n2`, `.n1`; `name` is "N5"…"N1"; easier levels sort
first, so `.n5 < .n1`.

### RubyMarkup

`RubyMarkup.parse(_:) -> [Piece]` (each `base` and `reading`) and
`RubyMarkup.plainText(_:)`, which strips markup: `{漢字|かんじ}を読む` is
`漢字を読む`.

### RubyModelReadings

`RubyModelReadings.prewarm(_ model: any LanguageModel = SystemLanguageModel.default)`
loads a model before the first question. Benchmarking APIs are SPI, behind
`@_spi(Experiments) import RubyCore`.

## RubyMeCab

```swift
RubyMeCabAnalyzer(dictionary url: URL)  // a compiled IPAdic or UniDic folder
let format: RubyMeCabAnalyzer.Format    // .ipadic or .unidic, read from dicrc
```

A `final class`, `Sendable`, compared by identity. See
[analyzers.md](analyzers.md).

## RubyTransliteration

### RubyRomanization

`.hepburn` (Tōkyō), `.kunrei` (Tôkyô), `.nippon` (Tôkyô, with wo for を),
`.passport` (Tokyo, shimbun), `.wapuro` (as typed: toukyou), `.turkish`
(şinbun), `.polivanov` (Cyrillic: симбун), `.hangul` (신분), or
`RubyRomanization(_ style: some RubyTransliterationStyle)`.

```swift
func transliterate(_ kana: String, pronunciation: String? = nil) -> String
func transliterate(_ phrase: RubyPhrase) -> String
```

### RubyTableStyle

A style written as data; start from a built-in one and change what differs:

```swift
var style = RubyTableStyle.hepburn
style.syllables["し"] = "si"                       // a kana written differently
style.words["東京"] = "Tokyo"                       // a word written its own way
style.longVowels = .marked(RubyTableStyle.circumflexes) // or .marked([:]) for none, or .spelled
style.particles = .spelled                         // は as ha, へ as he
style.capitalizesProperNouns = false

RubyText(text)
    .rubyStyle(.romaji)
    .rubyRomanization(RubyRomanization(style))
```

Other properties: `nasal`, `nasalBeforeVowel` (n'), `nasalBeforeLabial` (m
in shimbun), `geminates`, `syllablesAfterVowel`, `capitals`, `punctuation`.
`RubyTableStyle(name:onsets:vowels:palatalVowels:exceptions:longVowels:)`
builds a style for another alphabet from consonants and vowels.
`RubyTransliterationValidator.validate(_:)` lists kana and phrases a style
leaves unwritten. For a system a table can't express, conform to
`RubyTransliterationStyle` (`func transliterate(_ phrase: RubyPhrase) -> String`).

### RubyKana

`RubyKana.hiragana(_:)` and `RubyKana.katakana(_:)` convert between kana,
keeping ー and widening half-width katakana. `Character` gains `isKanji`,
`isKana`, `isHiragana`, `isKatakana` and `isJapanese`.
