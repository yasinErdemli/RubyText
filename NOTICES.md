# Notices

RubyText's code is under the Apache License 2.0; see [LICENSE](LICENSE).
The data and dependencies below keep their own licences.

## In the package

### JLPT kanji levels

`Sources/RubyCore/RubyJLPT.swift` holds the JLPT level of each kanji, from
Jonathan Waller's JLPT lists ([tanos.co.uk/jlpt](https://www.tanos.co.uk/jlpt/)),
which he shares under Creative Commons Attribution: they may be used for any
purpose with credit to his site. They're taken as compiled in
[kanji-data](https://github.com/davidluzgouveia/kanji-data), MIT License,
Copyright (c) 2019 David Gouveia.

Apps that show JLPT levels, such as in word details or JLPT word colors,
should credit the lists, for example in an About screen: "JLPT levels from
Jonathan Waller's JLPT Resources (tanos.co.uk)."

## Dependencies

### Mecab-Swift

[Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift), the Swift wrapper
RubyCore analyzes text with, is under the MIT License, Copyright (c) 2019
telethon k.k.

### MeCab

Mecab-Swift includes [MeCab](https://taku910.github.io/mecab/), copyrighted
free software by Taku Kudo and Nippon Telegraph and Telephone Corporation,
released under any of the GPL, the LGPL, or the BSD License. Its licence
files are in Mecab-Swift's `Sources/mecab/mecab` folder.

### JMdict sample in the tests

`Tests/RubyCoreTests/Fixtures/jmdict-sample.sqlite` holds a few entries from
JMdict, the property of the Electronic Dictionary Research and Development
Group, used in conformance with the
[Group's licence](https://www.edrdg.org/edrdg/licence.html) and under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). It's only
used by the tests, and isn't part of any product.

## Dictionaries apps supply

RubyText bundles no dictionary. Apps choose and bundle their own, under the
dictionary's licence.

### IPAdic

The dictionary MeCab reads words and readings with, such as the one
Mecab-Swift's `IPADic` product provides, is Copyright Nara Institute of
Science and Technology. It may be used and redistributed with its copyright
notice and licence paragraphs, which are in its `COPYING` file.

### UniDic

UniDic, which MeCab can read in place of IPAdic, is copyrighted free
software by the UniDic Consortium, released under any of the GPL, the LGPL,
or the BSD License. Apps that bundle it can choose the BSD License, which
asks them to reproduce its copyright notice and conditions; they're in the
`BSD` file, or the `licenses` folder, of the copy they use.

The tests read UniDic only where `RUBYTEXT_UNIDIC` points to a copy; none is
part of this repository.

### JMdict

Word details show definitions from a database apps build from
[JMdict](https://www.edrdg.org/jmdict/j_jmdict.html), the property of the
Electronic Dictionary Research and Development Group, used in conformance
with the [Group's licence](https://www.edrdg.org/edrdg/licence.html). The
data, and databases built from it, are under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

The licence asks apps that use it to:

- Acknowledge it where the app lists its sources, such as an About screen:
  "This app uses the JMdict dictionary files. These files are the property of
  the Electronic Dictionary Research and Development Group, and are used in
  conformance with the Group's licence," with a link to
  https://www.edrdg.org/. Word details show `RubyDictionary.credit` under the
  definitions as well, which isn't enough on its own.
- Keep the database under CC BY-SA 4.0, separate from the app's code.
- Update the data regularly, as JMdict changes.
