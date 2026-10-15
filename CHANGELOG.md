# Changelog

RubyText follows [semantic versioning](https://semver.org). Notable changes
are listed here, newest first.

## Unreleased

- No line starts with 。, 、, 」, ー, a small kana or another character
  Japanese keeps off the start of a line. Breaking between phrases, a
  phrase wider than the line, as in large accessibility text sizes, was
  broken after the last character that fit, which could leave 。 alone on
  the next line (お願いします / 。). `RubyText` now checks its lines once
  they're laid out and breaks such a paragraph between characters
  instead, until the text, its font or its width changes. Text whose
  phrases fit keeps breaking between them.
- `.rubyLineBreaking(.anywhere)` breaks with the strict rules, which also
  keep ゃ, ッ and ー off the start of a line, as its documentation said.

## 1.3.0 — 2026-10-12

- `rubyWordWeights(_:)` sets chosen words in their own weight, such as a
  grammar point's form in bold, by ID with `RubyWordWeights.wordIDs(_:)` or
  as written with `.words(_:)`, bold unless you give another weight. Their
  furigana and romaji take the weight too. It combines with
  `rubyWordColors(_:in:)` to make words bold as well as colored.

## 1.2.0 — 2026-10-12

- `RubySegment.wordID`: consecutive segments with the same ID are one word,
  so a word given in pieces, with a reading over each kanji (食|べ|物), is
  tapped, colored, spaced and read by VoiceOver as one. The ID comes back in
  `RubyWordInfo.wordID`.
- `RubyWordColors.wordIDs(_:)` colors words by ID, and not others written
  the same. `RubyFuriganaFilter.showing(wordIDs:)` shows every reading of
  chosen words, whatever their kanji, so a word still being learned keeps
  its furigana while the same kanji elsewhere stay bare.
- `RubyReader.play(narration:for:phraseStarts:end:)` plays a recording of
  segments with the time each phrase starts, with no speech recognition.
- In segments you give, `attachesToPrevious: false` always starts a phrase,
  so 今日｜何を is spaced and read as two phrases. A kanji word after an
  all-kanji one used to continue it, as it still does in analyzers'
  segments, where it's usually a compound split apart (経済|政策).
- Kana segments you give without a reading are read as written, so they
  get romaji.

## 1.1.0 — 2026-10-11

- MeCab is a package trait, on by default, so nothing changes for apps that
  use RubyMeCab. An app that doesn't can depend on RubyText with
  `traits: []`, and Swift Package Manager no longer downloads Mecab-Swift and
  its dictionaries, about 400 MB in every build folder. Without the trait,
  `RubyMeCab` is an empty module.
- A skill for AI coding agents, in `skills/rubytext`, with references for
  the whole API, analyzers and language models. Claude Code installs it from
  this repository as a plugin marketplace, and other agents with
  `npx skills add yasinErdemli/RubyText`.

## 1.0.0 — 2026-10-11

The first release.

### Products

- `RubyCore` finds words with any analyzer you choose, and links no
  tokenizer. `RubyMeCab` is the analyzer RubyText includes: MeCab with a
  dictionary in IPAdic's or UniDic's format, which you supply, told apart
  by its `dicrc`. UniDic, larger than IPAdic, reads more recent words
  right: 39 or 42 of 50 for UniDic 2.1.2 or 3.1, against 36. An analyzer
  only has to give segments with readings, in hiragana or katakana;
  grammar is optional, and the "Using Any Analyzer" article lists what
  each part adds, with an example on Apple's built-in tokenizer.

### Readings

- Readings found on device: MeCab with IPAdic or UniDic, behind the
  `RubyAnalyzer` protocol, with rules for numbers, dates and counters (3日 →
  みっか, 2026年 → にせんにじゅうろくねん) and for set phrases (一日中,
  大家さん, お母さん, 十人十色), which also cover for analyzers that split
  them into shorter words. 日本 reads にほん, as most people say it, though
  analyzers read it にっぽん; names that use にっぽん, such as 日本銀行, keep
  it.
- Readings that depend on meaning chosen by a language model with
  `rubyModelReadings()`: 辛い as からい for spicy food, 人気 as ひとけ for
  people around. Apple's on-device model answers by default, where Apple
  Intelligence is available; `model:` takes any FoundationModels
  `LanguageModel`, such as `PrivateCloudComputeLanguageModel()` for apps
  with its entitlement, or a model from another provider that supports
  guided generation. It knows 64 such words, from 金 (かね or きん) and
  表 (おもて or ひょう) to 一途 (いちず or いっと). The model says what the
  word means before choosing, with the sentences around it. With
  `updates: .asAnswered`, each reading changes as soon as the model
  answers, so long texts correct themselves as it works.
  `RubyModelReadings.prewarm(_:)` loads a model ahead of time; the
  questions it's asked and the ways of asking that the benchmark compares
  are SPI, with `@_spi(Experiments)`.
- `{base|reading}` markup and `RubyText(segments:)` for readings you supply.
  Markup is read the way `Text` reads Markdown: in literals and with
  `RubyText(markup:)`, while a `String` is shown as written. Each reading
  records where it came from, as `RubyReadingSource`.
- Readings in code with string interpolation, as `RubyString`:
  `\(base, reading:)`, `\(unannotated:)` for text that's never annotated,
  and `RubyStringConvertible` for your own types, with
  `PersonNameComponents` read with their phonetic names. The pieces are
  analyzed as one text, and markup in interpolated strings shows as
  written. `RubyText` literals aren't localized; pass a
  `LocalizedStringResource` for localized text.
- 259 sentences for the words read by meaning: 140 read correctly by the
  dictionary, 240 with Apple's on-device model.
- A benchmark of 255 words in context: 241 read correctly, 254 with the
  model.

### Display

- `RubyText`: furigana above by default, romaji above or below, or both,
  inherited through the environment like other text styles, with animated
  changes that respect Reduce Motion. `import RubyUI` imports everything it
  uses.
- Long text never holds up the interface: `RubyText` analyzes short text as
  it appears, and text over 200 UTF-16 code units off the main actor,
  showing it at once and fading its readings in. `RubyReader` analyzes long
  text the same way before reading, while `isPreparing` is true, as do
  readings by meaning and aligning a recording.
- Furigana in hiragana, katakana or romaji, or inline in parentheses.
  Readings keep their natural spacing, centered over their kanji; long ones
  flow over neighboring kana and get space around their word, never inside
  it.
- Lines break between phrases, or anywhere with `.rubyLineBreaking(.anywhere)`,
  which still keeps each paragraph's last word together so no line holds a
  single kana (す。). SwiftUI's `lineLimit(_:)` and `truncationMode(_:)`
  apply, with readings only over the text shown.
- Whole text written in hiragana, katakana or romaji with
  `rubyTranscription(_:)`, rolling glyph by glyph into the new text. One
  `RubyScript` type names the script for furigana and for the whole text.
- Romaji in Hepburn, Kunrei-shiki, Nihon-shiki, passport style, wāpuro (as
  typed) or Hepburn for Turkish readers, and readings in Cyrillic
  (Polivanov) or Hangul, set with `rubyRomanization(_:)`. Names of people
  and places start with a capital, as the dictionary marks them: Tōkyō,
  İbaraki in Turkish.
- Learner tools: furigana only above a JLPT level, word colors by part of
  speech, JLPT level (`.jlpt(above: .n4)` for the levels a learner doesn't
  know yet) or vocabulary, with `color(for:)` for a key to the colors, and
  space between words or phrases.
- Word colors by where each reading came from, `.readingSources`, to check
  readings: yours, rules', and the model's.
- Word details with the reading, dictionary form, part of speech, JLPT
  levels and JMdict definitions.
- Read aloud with `RubyReader`, synthesized or from a recording, with the
  phrase being spoken emphasized. It reads with the analyzer and spoken
  readings of the views it's attached to.

### Accessibility

- VoiceOver says the readings voices would get wrong as furigana show them,
  set with `rubySpokenReadings(_:)`; braille shows the text as written.
- VoiceOver users open word details through each word's accessibility
  action.

### Localization

- RubyText's own text, in word details, part-of-speech names, VoiceOver
  hints and errors, is in English and 16 other languages, from string
  catalogs in RubyCore and RubyUI used through their generated symbols.

### Plain text

- `RubyConverter` writes text in kana or romaji, or with inline readings,
  as plain strings.
- `RubyTransliteration`: kana to romaji, Cyrillic or Hangul, hiragana and
  katakana, and `Character` properties such as `isKanji` and `isKana`, with
  only the standard library. Kana are read once into a
  `RubyPhrase` of `RubyMora`s, settling long vowels, particles, っ and ん, and
  a `RubyTransliterationStyle` writes them: `RubyTableStyle` as data you can
  change, or your own type. `RubyTransliterationValidator` checks a style
  against every mora.
