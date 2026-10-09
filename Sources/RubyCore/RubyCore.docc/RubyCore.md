# ``RubyCore``

Find the readings of Japanese text, and work with them as plain data.

## Overview

RubyCore finds words and their readings, and writes text out in kana or
romaji, without any user interface. `RubyUI` draws with it; use it directly
for search, sharing, export, or your own views.

```swift
let analyzer = RubyMeCabAnalyzer(dictionary: dictionaryURL)
let converter = RubyConverter(analyzer: analyzer)
converter.convert("今日はコーヒーを飲んだ。", to: .hiragana)  // きょうはコーヒーをのんだ。
converter.annotate("東京へ行きたい。", with: .hiragana)    // 東京（とうきょう）へ行（い）きたい。
```

Readings are resolved in layers: readings you supply in `{base|reading}`
markup or in a ``RubyString``, then rules for numbers, counters and phrases, then optionally Apple's
on-device model for words whose reading depends on meaning, then the
dictionary. Each reading records its layer as a ``RubyReadingSource``.

## Topics

### Finding readings

- ``RubyAnalyzer``
- ``RubyMeCabAnalyzer``
- ``RubySegment``
- ``RubyReadingSource``

### Giving readings

- ``RubyString``
- ``RubyStringConvertible``
- ``RubyMarkup``

### Readings by meaning

- ``RubyModelReadings``

### Writing text out

- ``RubyConverter``
- ``RubyScript``

### Words

- ``RubyWordInfo``
- ``RubyPartOfSpeech``
- ``RubyJLPTLevel``
- ``RubyDictionary``

### Speech

- ``RubySpokenReadings``
