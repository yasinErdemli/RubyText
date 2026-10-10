import Foundation
import RubyCore
import RubyMeCab
import Testing

/// Words that became common since IPAdic was last updated in 2007, or that
/// it reads wrong: names, slang, and terms from the news, each with its
/// usual reading. They measure how current a dictionary is; RubyText has
/// no rules for them.
let recentWords: [(word: String, reading: String)] = [
    ("令和元年", "れいわがんねん"), ("推し活", "おしかつ"), ("コロナ禍", "ころなか"),
    ("在宅勤務", "ざいたくきんむ"), ("線状降水帯", "せんじょうこうすいたい"), ("忖度", "そんたく"),
    ("爆買い", "ばくがい"), ("闇バイト", "やみばいと"), ("生成AI", "せいせいAI"),
    ("鬼滅の刃", "きめつのやいば"), ("藤井聡太", "ふじいそうた"), ("大谷翔平", "おおたにしょうへい"),
    ("渋谷区", "しぶやく"), ("高輪ゲートウェイ", "たかなわげーとうぇい"), ("岸田首相", "きしだしゅしょう"),
    ("羽生結弦", "はにゅうゆづる"), ("婚活", "こんかつ"), ("終活", "しゅうかつ"),
    ("断捨離", "だんしゃり"), ("女子会", "じょしかい"), ("既読スルー", "きどくするー"),
    ("人工知能", "じんこうちのう"), ("仮想通貨", "かそうつうか"), ("二刀流", "にとうりゅう"),
    ("寄り添う", "よりそう"), ("真逆", "まぎゃく"), ("神対応", "かみたいおう"),
    ("炎上", "えんじょう"), ("拡散", "かくさん"), ("投稿", "とうこう"),
    ("配信者", "はいしんしゃ"), ("陽キャ", "ようきゃ"), ("陰キャ", "いんきゃ"),
    ("尊い", "とうとい"), ("詰んだ", "つんだ"), ("萌え", "もえ"),
    ("地球温暖化", "ちきゅうおんだんか"), ("少子高齢化", "しょうしこうれいか"), ("働き方改革", "はたらきかたかいかく"),
    ("特殊詐欺", "とくしゅさぎ"), ("熱中症", "ねっちゅうしょう"), ("線引き", "せんびき"),
    ("不適切", "ふてきせつ"), ("自撮り", "じどり"), ("顔認証", "かおにんしょう"),
    ("電子決済", "でんしけっさい"), ("置き配", "おきはい"), ("時短", "じたん"),
    ("三密", "さんみつ"), ("親ガチャ", "おやがちゃ"),
]

/// The words of `recentWords` `analyzer` reads wrong, with how it reads
/// them.
func misreadRecentWords(with analyzer: some RubyAnalyzer) -> [(word: String, reading: String)] {
    recentWords.compactMap { word, expected in
        let actual = reading(of: word, in: RubyContent.content(for: word, analyzer: analyzer)) ?? "(not found)"
        return actual == expected ? nil : (word, actual)
    }
}

@Suite struct RecentWordsBenchmarkTests {
    @Test func casesAreUnique() {
        #expect(Set(recentWords.map(\.word)).count == recentWords.count)
    }

    /// Prints how many recent words IPAdic reads right, and UniDic where
    /// `RUBYTEXT_UNIDIC` points to it.
    @Test func score() {
        var analyzers: [(String, RubyMeCabAnalyzer)] = [("IPAdic", .ipadic)]
        if let unidic { analyzers.append(("UniDic", unidic)) }
        for (name, analyzer) in analyzers {
            let wrong = misreadRecentWords(with: analyzer)
            print("Recent words, \(name): \(recentWords.count - wrong.count) of \(recentWords.count)")
            for (word, reading) in wrong {
                print("- \(word) → \(reading)")
            }
        }
    }
}
