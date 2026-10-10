# ``RubyMeCab``

Find words and readings with MeCab and a dictionary in IPAdic's format.

## Overview

RubyMeCab is one analyzer for RubyText, separate so that apps using another
link nothing they don't need. It reads with MeCab, whose part-of-speech
information also groups words into reading phrases and colors them for
learners.

RubyText bundles no dictionary. The simplest to use is the one Mecab-Swift's
`IPADic` product provides:

```swift
import IPADic
import RubyMeCab
import RubyUI

let analyzer = RubyMeCabAnalyzer(dictionary: IPADic().url)

ContentView()
    .rubyAnalyzer(analyzer)
```

For another dictionary or tokenizer, write your own `RubyAnalyzer`, as
RubyCore's "Using Any Analyzer" article shows.

## Topics

- ``RubyMeCabAnalyzer``
