# ``RubyTransliteration``

Write kana in romaji, hiragana or katakana, with only the standard library.

## Overview

RubyTransliteration needs no dictionary: it converts kana you already have.

```swift
RubyRomaji.romanize("とうきょう", system: .hepburn)  // tōkyō
RubyRomaji.romanize("とうきょう", system: .nippon)   // tôkyô
RubyKana.katakana("ひらがな")                        // ヒラガナ
```

To find the readings of kanji, use `RubyCore`.

## Topics

### Romaji

- ``RubyRomaji``
- ``RubyRomanization``

### Kana

- ``RubyKana``
