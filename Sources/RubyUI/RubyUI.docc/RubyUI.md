# ``RubyUI``

Show Japanese text with furigana and romaji in SwiftUI.

## Overview

``RubyText`` shows Japanese text with readings above its kanji, romaji above
or below, or both, and finds the readings on device. Use it like `Text`, and
set annotations through the environment, on the text or any view above it:

```swift
RubyText("{今日|きょう}は日本語を勉強しています。")
    .font(.title)
    .rubyStyle([.furigana, .romaji])
```

Readings come from the analyzer you set once, near the root of your app,
such as MeCab with the IPAdic dictionary your app bundles. Without one, only
readings you write in `{base|reading}` markup show.

```swift
ContentView()
    .rubyAnalyzer(RubyMeCabAnalyzer(dictionary: dictionaryURL))
```

## Topics

### Showing text

- ``RubyText``
- ``SwiftUICore/View/rubyAnalyzer(_:)``
- ``SwiftUICore/View/rubyModelReadings(_:updates:)``
- ``RubyModelReadingUpdates``

### Choosing annotations

- ``SwiftUICore/View/rubyStyle(_:)``
- ``RubyStyle``
- ``SwiftUICore/View/rubyFuriganaScript(_:)``
- ``SwiftUICore/View/rubyFuriganaPosition(_:)``
- ``RubyFuriganaPosition``
- ``SwiftUICore/View/rubyRomanization(_:)``
- ``SwiftUICore/View/rubyFurigana(_:)``
- ``RubyFuriganaFilter``
- ``SwiftUICore/View/rubyDigitReadingsHidden(_:)``

### Writing text out

- ``SwiftUICore/View/rubyTranscription(_:)``

### Spacing and line breaks

- ``SwiftUICore/View/rubySpacing(_:)``
- ``RubySpacing``
- ``SwiftUICore/View/rubyLineBreaking(_:)``
- ``RubyLineBreaking``

### Coloring words

- ``SwiftUICore/View/rubyWordColors(_:in:)``
- ``RubyWordColors``
- ``RubyWordColorPlacement``

### Word details

- ``SwiftUICore/View/rubyWordDetails(_:)``
- ``SwiftUICore/View/onRubyWordTap(perform:)``
- ``SwiftUICore/View/rubyDictionary(_:)``
- ``RubyWordDetailView``

### Reading aloud

- ``RubyReader``
- ``SwiftUICore/View/rubyReader(_:)``
- ``SwiftUICore/View/rubyEmphasis(_:)``
- ``RubyEmphasis``

### VoiceOver

- ``SwiftUICore/View/rubySpokenReadings(_:)``
