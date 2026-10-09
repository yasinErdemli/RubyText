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
  Each reading records where it came from, as `ReadingSource`.
- A benchmark of 255 words in context: 241 read correctly, 254 with the
  model.

### Display

- `RubyText`: furigana above, romaji above or below, or both, inherited
  through the environment like other text styles, with animated changes that
  respect Reduce Motion.
- Furigana in hiragana, katakana or romaji, or inline in parentheses.
- Whole text written in hiragana, katakana or romaji with
  `rubyTranscription(_:)`, rolling glyph by glyph into the new text.
- Romaji in Hepburn, Nihon-shiki or passport style.
- Learner tools: furigana only above a JLPT level, word colors by part of
  speech, JLPT level or vocabulary, and space between words or phrases.
- Word colors by where each reading came from, `.readingSources`, to check
  readings: yours, rules', and the model's.
- Word details with the reading, dictionary form, part of speech, JLPT
  levels and JMdict definitions.
- Read aloud with `RubyReader`, synthesized or from a recording, with the
  phrase being spoken emphasized.

### Accessibility

- VoiceOver says the readings voices would get wrong as furigana show them,
  set with `rubySpokenReadings(_:)`; braille shows the text as written.
- VoiceOver users open word details through each word's accessibility
  action.

### Plain text

- `RubyConverter` writes text in kana or romaji, or with inline readings,
  as plain strings.
- `RubyTransliteration`: kana to romaji, hiragana and katakana, with only the
  standard library.
