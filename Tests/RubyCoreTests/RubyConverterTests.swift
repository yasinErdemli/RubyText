// Reads text with MeCab and IPAdic, so only with the MeCab trait.
#if MeCab
import RubyCore
import RubyMeCab
import RubyTransliteration
import Testing

@Suite struct RubyConverterTests {
    private let converter = RubyConverter(analyzer: RubyMeCabAnalyzer.ipadic)
    private static let sentence = "感じ取れたら手を繋ごう"

    @Test func hiragana() {
        #expect(converter.convert(Self.sentence, to: .hiragana) == "かんじとれたらてをつなごう")
        // Loanwords stay in katakana, unless they're asked for in hiragana,
        // which keeps the long-vowel mark.
        #expect(converter.convert("今日はコーヒーを飲んだ。", to: .hiragana) == "きょうはコーヒーをのんだ。")
        #expect(converter.convert("今日はコーヒーを飲んだ。", to: .hiragana(loanwords: .hiragana)) == "きょうはこーひーをのんだ。")
    }

    @Test func katakana() {
        #expect(converter.convert(Self.sentence, to: .katakana) == "カンジトレタラテヲツナゴウ")
        #expect(converter.convert("今日はコーヒーを飲んだ。", to: .katakana) == "キョウハコーヒーヲノンダ。")
    }

    @Test func romaji() {
        #expect(converter.convert(Self.sentence, to: .romaji) == "kanjitoretara te o tsunagō")
        #expect(converter.convert("今日はコーヒーを飲んだ。", to: .romaji) == "kyō wa kōhī o nonda.")
    }

    @Test func romanizationSystems() {
        let sentence = "東京へ行こう。お茶を飲む。"
        #expect(converter.convert(sentence, to: .romaji) == "Tōkyō e ikō. ocha o nomu.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .hepburn) == "Tōkyō e ikō. ocha o nomu.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .nippon) == "Tôkyô e ikô. otya wo nomu.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .passport) == "Tokyo e iko. ocha o nomu.")
        #expect(converter.annotate("東京へ行きたい。", with: .romaji, romanization: .nippon) == "東京（tôkyô）へ行（i）きたい。")
        #expect(converter.convert(sentence, to: .romaji, romanization: .kunrei) == "Tôkyô e ikô. otya o nomu.")
        // Typed romaji spell long vowels and particles as written.
        #expect(converter.convert(sentence, to: .romaji, romanization: .wapuro) == "toukyou he ikou. ocha wo nomu.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .turkish) == "Tôkyô e ikô. oça o nomu.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .polivanov) == "Токё э ико. отя о ному.")
        #expect(converter.convert(sentence, to: .romaji, romanization: .hangul) == "도쿄 에 이코. 오차 오 노무.")
    }

    /// Markup counts in literals and in `RubyString(markup:)`; a `String`
    /// is read as written.
    @Test func stringsAreReadAsWritten() {
        let loaded = "{今日|こんにち}は"
        #expect(converter.convert(RubyString(markup: loaded), to: .hiragana) == "こんにちは")
        #expect(converter.convert(loaded, to: .hiragana).contains("{"))
        #expect(converter.annotate(loaded, with: .hiragana).contains("|"))
    }

    /// Names the dictionary knows start with a capital.
    @Test func namesAreCapitalized() {
        #expect(converter.convert("田中さんは東京に住んでいる。", to: .romaji) == "Tanaka san wa Tōkyō ni sunde iru.")
        #expect(converter.convert("茨城に住んでいる。", to: .romaji, romanization: .turkish) == "İbaraki ni sunde iru.")
    }

    @Test func romajiPunctuation() {
        #expect(converter.convert("「はい」と言った。それから、帰った。", to: .romaji) == "“hai” to itta. sorekara, kaetta.")
        #expect(converter.convert("一行目。\n二行目", to: .romaji).contains(".\n"))
    }

    @Test func otherTextStays() {
        #expect(converter.convert("iPhoneで読んだ。", to: .hiragana) == "iPhoneでよんだ。")
        #expect(converter.convert("iPhoneで読んだ。", to: .romaji) == "iPhone de yonda.")
    }

    @Test func numbers() {
        #expect(converter.convert("3日に行く。", to: .hiragana) == "みっかにいく。")
    }

    @Test func annotateWithKana() {
        #expect(converter.annotate(Self.sentence, with: .hiragana) == "感（かん）じ取（と）れたら手（て）を繋（つな）ごう")
        #expect(converter.annotate(Self.sentence, with: .katakana) == "感（カン）じ取（ト）れたら手（テ）を繋（ツナ）ごう")
    }

    @Test func annotateWithRomaji() {
        #expect(converter.annotate("東京へ行きたい。", with: .romaji) == "東京（tōkyō）へ行（i）きたい。")
    }

    @Test func annotateWithOtherParentheses() {
        #expect(converter.annotate("東京へ行きたい。", with: .hiragana, parentheses: ("(", ")")) == "東京(とうきょう)へ行(い)きたい。")
    }

    @Test func markupReadings() {
        // Readings you supply win, and keep their kana unless asked for another script.
        #expect(converter.annotate("{本気|マジ}で{今日|こんにち}", with: .hiragana) == "本気（マジ）で今日（こんにち）")
        #expect(converter.annotate("{本気|マジ}で", with: .katakana) == "本気（マジ）で")
        #expect(converter.convert("{本気|マジ}で", to: .hiragana) == "マジで")
        #expect(converter.convert("{本気|マジ}で", to: .hiragana(loanwords: .hiragana)) == "まじで")
    }

    @Test func withoutAnalyzer() {
        // Only markup readings are known; other kanji stay.
        let converter = RubyConverter()
        #expect(converter.convert("{今日|きょう}は晴れ", to: .hiragana) == "きょうは晴れ")
        #expect(converter.annotate("{今日|きょう}は晴れ", with: .hiragana) == "今日（きょう）は晴れ")
        #expect(converter.convert("{今日|きょう}、はい", to: .romaji) == "kyō, hai")
    }
}
#endif
