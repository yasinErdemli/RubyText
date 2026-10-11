# ``RubyMeCab``

Find words and readings with MeCab and a dictionary in IPAdic's or UniDic's
format.

## Overview

RubyMeCab is one analyzer for RubyText, separate so that apps using another
link nothing they don't need. It reads with MeCab, whose part-of-speech
information also groups words into reading phrases and colors them for
learners.

RubyMeCab needs RubyText's `MeCab` package trait, which is on by default.
An app that depends on RubyText with `traits: []` never downloads
Mecab-Swift, and RubyMeCab is then an empty module.

RubyText bundles no dictionary. The simplest to use is the IPAdic that
Mecab-Swift's `IPADic` product provides:

```swift
import IPADic
import RubyMeCab
import RubyUI

let analyzer = RubyMeCabAnalyzer(dictionary: IPADic().url)

ContentView()
    .rubyAnalyzer(analyzer)
```

### Choosing a dictionary

`RubyMeCabAnalyzer` reads either of MeCab's two main dictionaries, and
tells them apart by their `dicrc` file:

| | IPAdic | UniDic 2.1.2 | UniDic 3.1 |
| --- | --- | --- | --- |
| Size | 50 MB | 250 MB | 770 MB |
| Last updated | 2007 | 2013 | 2021 |
| Reading benchmark, of 255 | 241 | 243 | 242 |
| Recent words, of 50 | 36 | 39 | 42 |

IPAdic is small and comes with Mecab-Swift. UniDic, from the National
Institute for Japanese Language and Linguistics, knows more recent words
(令和 as れいわ rather than りょうわ, 終活, 既読, 自撮り) and splits text into
shorter words. RubyText's rules for numbers and phrases work on top of
either.

To use UniDic, bundle or download its compiled folder, such as the
`dicdir` folder of the `unidic-lite` (2.1.2) or `unidic` (3.1) Python
packages, and pass its location:

```swift
let analyzer = RubyMeCabAnalyzer(dictionary: unidicFolderURL)
// analyzer.format == .unidic
```

UniDic is under the GPL, the LGPL, or the BSD License, as you choose; see
NOTICES.md. For another dictionary or tokenizer, such as Sudachi, write
your own `RubyAnalyzer`, as RubyCore's "Using Any Analyzer" article shows.

## Topics

- ``RubyMeCabAnalyzer``
