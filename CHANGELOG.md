# Changelog

RubyText follows [semantic versioning](https://semver.org). Notable changes
are listed here, newest first.

## Unreleased

The first release.

### Readings

- Readings found on device: MeCab with IPAdic, behind the `RubyAnalyzer`
  protocol, with rules for numbers, dates and counters (3日 → みっか,
  2026年 → にせんにじゅうろくねん) and for set phrases (一日中, 大家さん).
- Readings that depend on meaning chosen by Apple's on-device model with
  `rubyModelReadings()`, where Apple Intelligence is available: 辛い as からい
  for spicy food, 人気 as ひとけ for people around. It says what the word
  means before choosing, with the sentences around it, which `RubyModelOptions`
  can change, along with asking about a text's words together and using
  Apple's larger model over Private Cloud Compute, for apps with its
  entitlement. With `updates: .asAnswered`,
  each reading changes as soon as the model answers, so long texts correct
  themselves as it works. `RubyModelReadings` lists
  the questions the model is asked, asks them one at a time to time them,
  and prewarms the model.
- `{base|reading}` markup and `RubyText(segments:)` for readings you supply.
  Markup is read the way `Text` reads Markdown: in literals and with
  `RubyText(markup:)`, while a `String` is shown as written. Each reading
  records where it came from, as `ReadingSource`.
- Readings in code with string interpolation, as `RubyString`:
  `\(base, reading:)`, `\(unannotated:)` for text that's never annotated,
  and `RubyStringConvertible` for your own types, with
  `PersonNameComponents` read with their phonetic names. The pieces are
  analyzed as one text, and markup in interpolated strings shows as
  written. `RubyText` literals aren't localized; pass a
  `LocalizedStringResource` for localized text.
- A benchmark of 255 words in context: 241 read correctly, 254 with the
  model.

### Display

- `RubyText`: furigana above by default, romaji above or below, or both,
  inherited through the environment like other text styles, with animated
  changes that respect Reduce Motion. `import RubyUI` imports everything it
  uses.
- Furigana in hiragana, katakana or romaji, or inline in parentheses.
  Readings keep their natural spacing, centered over their kanji; long ones
  flow over neighboring kana and get space around their word, never inside
  it.
- Lines break between phrases, or anywhere with `.rubyLineBreaking(.anywhere)`,
  which still keeps each paragraph's last word together so no line holds a
  single kana (す。).
- Whole text written in hiragana, katakana or romaji with
  `rubyTranscription(_:)`, rolling glyph by glyph into the new text. One
  `RubyScript` type names the script for furigana and for the whole text.
- Romaji in Hepburn, Kunrei-shiki, Nihon-shiki, passport style, wāpuro (as
  typed) or Hepburn for Turkish readers, and readings in Cyrillic
  (Polivanov) or Hangul, set with `rubyRomanization(_:)`. Names of people
  and places start with a capital, as the dictionary marks them: Tōkyō,
  İbaraki in Turkish.
- Learner tools: furigana only above a JLPT level, word colors by part of
  speech, JLPT level or vocabulary, and space between words or phrases.
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

### Plain text

- `RubyConverter` writes text in kana or romaji, or with inline readings,
  as plain strings.
- `RubyTransliteration`: kana to romaji, Cyrillic or Hangul, hiragana and
  katakana, with only the standard library. Kana are read once into a
  `RubyPhrase` of `RubyMora`s, settling long vowels, particles, っ and ん, and
  a `RubyTransliterationStyle` writes them: `RubyTableStyle` as data you can
  change, or your own type. `RubyTransliterationValidator` checks a style
  against every mora.
