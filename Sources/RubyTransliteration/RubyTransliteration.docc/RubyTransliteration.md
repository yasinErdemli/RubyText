# ``RubyTransliteration``

Write kana in romaji, Cyrillic or Hangul, or in hiragana or katakana, with
only the standard library.

## Overview

RubyTransliteration needs no dictionary: it converts kana you already have.

```swift
RubyRomanization.hepburn.transliterate("とうきょう", pronunciation: "とーきょー")  // tōkyō
RubyRomanization.kunrei.transliterate("しんぶん")                                // sinbun
RubyRomanization.polivanov.transliterate("さむらい")                             // самурай
RubyRomanization.hangul.transliterate("さっぽろ")                                // 삿포로
RubyKana.katakana("ひらがな")                                                    // ヒラガナ
```

To find the readings of kanji, use `RubyCore`.

### Styles

The library reads kana once into a ``RubyPhrase``: its words, and the
``RubyMora``s they're spoken in. That's where kana edge cases are settled:
which small kana join the kana before them, which vowels are long, which は
and へ are particles, and what follows っ and ん. A style only decides how
to write each mora.

``RubyTableStyle`` writes most systems as data. Start from a built-in one
and change what differs:

```swift
var style = RubyTableStyle.hepburn
style.words["東京"] = "Tokyo"
style.longVowels = .marked(RubyTableStyle.circumflexes)
RubyText(text)
    .rubyStyle(.romaji)
    .rubyRomanization(RubyRomanization(style))
```

For systems a table can't express, conform to
``RubyTransliterationStyle``, as ``RubyHangulStyle`` does. Check any style
with ``RubyTransliterationValidator``.

## Topics

### Writing kana

- ``RubyRomanization``
- ``RubyRomaji``

### Styles

- ``RubyTransliterationStyle``
- ``RubyTableStyle``
- ``RubyHangulStyle``
- ``RubyTransliterationValidator``

### What styles receive

- ``RubyPhrase``
- ``RubyMora``

### Kana

- ``RubyKana``
