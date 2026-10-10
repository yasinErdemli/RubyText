import Foundation
import RubyTransliteration

/// Words whose reading depends on what they mean, which only the sentence
/// around them settles: 辛い is からい for spicy food and つらい for a hard
/// parting.
///
/// The model layer asks about these words only, and only chooses among the
/// readings listed here, never a reading of its own. Each reading comes
/// with its meaning, which is what the model judges: it picks the meaning
/// that fits more reliably than it picks a reading.
package nonisolated enum RubyHomographs {
    /// One way to read a word, as a dictionary lists it.
    package struct Sense: Hashable, Sendable {
        /// The word with its kana ending: 止める.
        package let word: String
        /// Its reading in hiragana: やめる.
        package let reading: String
        /// What the word means read this way, in English.
        package let meaning: String
        /// Whether the word, read this way, is a noun that doesn't
        /// inflect, so it only fits text written exactly as `word`: 臭い
        /// as におい, but not 臭く.
        package var isNoun = false
    }

    /// The readings `segment` could have, written the way the segment is
    /// (止め reads とめ or やめ), or `nil` if it isn't on the list or its
    /// reading is none of the listed ones.
    package static func choices(for segment: RubySegment) -> [RubyReadingChoice]? {
        guard let reading = segment.reading,
              let senses = senses[segment.word?.dictionaryForm ?? segment.base] ?? senses[segment.base]
        else { return nil }
        let choices = senses.compactMap { sense in
            Self.reading(of: segment.base, as: sense).map { RubyReadingChoice(reading: $0, meaning: sense.meaning) }
        }
        guard choices.count == senses.count, choices.contains(where: { $0.reading == reading }) else { return nil }
        return choices
    }

    /// The reading of `text`, an inflection of `sense.word`, when read as
    /// `sense`: 止め as やめる is やめ, 辛かっ as からい is からかっ.
    private static func reading(of text: String, as sense: Sense) -> String? {
        guard !sense.isNoun || text == sense.word else { return nil }
        let word = Array(sense.word)
        guard let lastKanji = word.lastIndex(where: \.isKanji) else { return nil }
        let stem = String(word[...lastKanji])
        let ending = String(word[(lastKanji + 1)...])
        guard text.hasPrefix(stem), sense.reading.hasSuffix(ending) else { return nil }
        return String(sense.reading.dropLast(ending.count)) + RubyKana.hiragana(String(text.dropFirst(stem.count)))
    }

    /// The list, by the word's dictionary form.
    private static let senses: [String: [Sense]] = Dictionary(
        grouping: [
            Sense(word: "人気", reading: "にんき", meaning: "popularity with people, customers or fans"),
            Sense(word: "人気", reading: "ひとけ", meaning: "human presence, people around, nearly always with a negative: 人気がない, a deserted place"),
            Sense(word: "辛い", reading: "からい", meaning: "spicy, hot or salty (the taste of food)"),
            Sense(word: "辛い", reading: "つらい", meaning: "painful, hard to bear"),
            Sense(word: "生物", reading: "せいぶつ", meaning: "living thing; biology"),
            Sense(word: "生物", reading: "なまもの", meaning: "raw or perishable food that spoils quickly"),
            Sense(word: "方", reading: "ほう", meaning: "side or direction; used in comparisons"),
            Sense(word: "方", reading: "かた", meaning: "person (polite)"),
            Sense(word: "止める", reading: "とめる", meaning: "stop something moving; park a vehicle; turn off"),
            Sense(word: "止める", reading: "やめる", meaning: "stop doing an activity; quit, give up, cancel"),
            Sense(word: "大家", reading: "おおや", meaning: "landlord"),
            Sense(word: "大家", reading: "たいか", meaning: "great master of an art"),
            Sense(word: "今日", reading: "きょう", meaning: "today"),
            Sense(word: "今日", reading: "こんにち", meaning: "the present era, modern times, nowadays"),
            Sense(word: "色紙", reading: "いろがみ", meaning: "colored paper for origami and crafts"),
            Sense(word: "色紙", reading: "しきし", meaning: "thick square card for autographs, poems or messages"),
            Sense(word: "寒気", reading: "さむけ", meaning: "a chill or shivering felt in the body"),
            Sense(word: "寒気", reading: "かんき", meaning: "cold air mass (in weather)"),
            Sense(word: "最中", reading: "さいちゅう", meaning: "in the middle of"),
            Sense(word: "最中", reading: "もなか", meaning: "monaka, a wafer sweet filled with bean paste"),
            Sense(word: "開く", reading: "ひらく", meaning: "open something; hold an event; bloom"),
            Sense(word: "開く", reading: "あく", meaning: "become open; a hole forms"),
            Sense(word: "空く", reading: "あく", meaning: "become vacant or unoccupied (a seat, room, time or hands)"),
            Sense(word: "空く", reading: "すく", meaning: "become less crowded (trains, roads, shops); get hungry"),
            Sense(word: "角", reading: "かく", meaning: "angle (in geometry)"),
            Sense(word: "角", reading: "かど", meaning: "corner of a street, room or object"),
            Sense(word: "角", reading: "つの", meaning: "horn or antler on an animal's head"),
            Sense(word: "市場", reading: "いちば", meaning: "a marketplace with stalls, such as a fish or vegetable market"),
            Sense(word: "市場", reading: "しじょう", meaning: "a market in economics: trade, demand, the stock market"),
            Sense(word: "生地", reading: "きじ", meaning: "cloth or fabric; dough or batter"),
            Sense(word: "生地", reading: "せいち", meaning: "the place where someone was born"),
            Sense(word: "風車", reading: "ふうしゃ", meaning: "a windmill or wind turbine"),
            Sense(word: "風車", reading: "かざぐるま", meaning: "a pinwheel, a toy that spins in the wind"),
            Sense(word: "一行", reading: "いっこう", meaning: "a group of people traveling together, a party"),
            Sense(word: "一行", reading: "いちぎょう", meaning: "one line of text"),
            Sense(word: "気質", reading: "きしつ", meaning: "a person's temperament or disposition"),
            Sense(word: "気質", reading: "かたぎ", meaning: "the spirit typical of a trade or kind of people (職人気質)"),
            Sense(word: "見物", reading: "けんぶつ", meaning: "going sightseeing; watching a show, game or event as a spectator"),
            Sense(word: "見物", reading: "みもの", meaning: "something worth seeing, a spectacle (〜は見物だ)"),
            Sense(word: "心中", reading: "しんじゅう", meaning: "a double or family suicide"),
            Sense(word: "心中", reading: "しんちゅう", meaning: "one's true feelings, what one thinks inside"),
            Sense(word: "分別", reading: "ふんべつ", meaning: "good sense, judgment, discretion"),
            Sense(word: "分別", reading: "ぶんべつ", meaning: "sorting into kinds, such as separating garbage"),
            Sense(word: "大事", reading: "だいじ", meaning: "important, precious; taking good care"),
            Sense(word: "大事", reading: "おおごと", meaning: "a serious matter, a big incident"),
            Sense(word: "目下", reading: "もっか", meaning: "at present, currently"),
            Sense(word: "目下", reading: "めした", meaning: "people below one in rank or age, subordinates"),
            Sense(word: "金星", reading: "きんせい", meaning: "Venus, the planet"),
            Sense(word: "金星", reading: "きんぼし", meaning: "a gold star; an upset win over a champion"),
            Sense(word: "末期", reading: "まっき", meaning: "the final stage or last period of an era, illness or process"),
            Sense(word: "末期", reading: "まつご", meaning: "a person's dying moments (末期の言葉, 末期の水)"),
            Sense(word: "一途", reading: "いちず", meaning: "single-minded, wholeheartedly devoted"),
            Sense(word: "一途", reading: "いっと", meaning: "a steady course or trend (増加の一途)"),
            Sense(word: "利益", reading: "りえき", meaning: "profit, gain, benefit"),
            Sense(word: "利益", reading: "りやく", meaning: "divine favor or blessing from gods or Buddha (ご利益)"),
            Sense(word: "床", reading: "ゆか", meaning: "the floor of a room"),
            Sense(word: "床", reading: "とこ", meaning: "a bed or bedding; the alcove of a Japanese room"),
            Sense(word: "縁", reading: "えん", meaning: "a relationship, tie or fate between people or things"),
            Sense(word: "縁", reading: "ふち", meaning: "an edge, rim or border"),
            Sense(word: "金", reading: "かね", meaning: "money, cash, funds"),
            Sense(word: "金", reading: "きん", meaning: "gold, the precious metal, as in jewelry, coins or medals"),
            Sense(word: "表", reading: "おもて", meaning: "the front or surface side; outside, outdoors"),
            Sense(word: "表", reading: "ひょう", meaning: "a table, chart or list"),
            Sense(word: "空", reading: "そら", meaning: "the sky"),
            Sense(word: "空", reading: "から", meaning: "empty, containing nothing"),
            Sense(word: "下", reading: "した", meaning: "below, under, beneath; lower"),
            Sense(word: "下", reading: "もと", meaning: "under someone's guidance, rule or protection (〜の下で)"),
            Sense(word: "方々", reading: "かたがた", meaning: "people (polite plural)"),
            Sense(word: "方々", reading: "ほうぼう", meaning: "here and there, everywhere"),
            Sense(word: "大勢", reading: "おおぜい", meaning: "a large number of people, a crowd"),
            Sense(word: "大勢", reading: "たいせい", meaning: "the general trend or overall situation"),
            Sense(word: "人事", reading: "じんじ", meaning: "personnel matters: hiring, transfers, promotions"),
            Sense(word: "人事", reading: "ひとごと", meaning: "other people's affairs, something that doesn't concern oneself"),
            Sense(word: "一角", reading: "いっかく", meaning: "a corner or section of an area; a narwhal"),
            Sense(word: "一角", reading: "ひとかど", meaning: "distinguished, respectable, quite a (person)"),
            Sense(word: "一目", reading: "ひとめ", meaning: "a glance, a single look (一目見る, 一目惚れ)"),
            Sense(word: "一目", reading: "いちもく", meaning: "respect for someone as better than oneself, in the idiom 一目置く; one stone in Go"),
            Sense(word: "初日", reading: "しょにち", meaning: "the first day of an event, run or tournament"),
            Sense(word: "初日", reading: "はつひ", meaning: "the first sunrise of the New Year"),
            Sense(word: "小人", reading: "こびと", meaning: "a dwarf or tiny person in tales"),
            Sense(word: "小人", reading: "しょうにん", meaning: "a child, for tickets and admission fees"),
            Sense(word: "弾く", reading: "ひく", meaning: "play a string or keyboard instrument"),
            Sense(word: "弾く", reading: "はじく", meaning: "flick or snap with a finger; repel (water)"),
            Sense(word: "抱く", reading: "だく", meaning: "hold in one's arms, hug"),
            Sense(word: "抱く", reading: "いだく", meaning: "harbor a feeling, hope, dream or doubt"),
            Sense(word: "被る", reading: "かぶる", meaning: "put on or wear on the head; be covered with (dust, water)"),
            Sense(word: "被る", reading: "こうむる", meaning: "suffer or receive (damage, loss, a favor)"),
            Sense(word: "汚す", reading: "よごす", meaning: "make dirty, soil, stain"),
            Sense(word: "汚す", reading: "けがす", meaning: "disgrace or dishonor (a name, honor, a sacred place)"),
            Sense(word: "解く", reading: "とく", meaning: "solve or answer (a problem); clear up (a misunderstanding); lift (a ban)"),
            Sense(word: "解く", reading: "ほどく", meaning: "undo or untie by hand (a knot, laces, a ribbon)"),
            Sense(word: "臭い", reading: "くさい", meaning: "smelly, stinking; suspicious"),
            Sense(word: "臭い", reading: "におい", meaning: "a smell or odor (the noun)", isNoun: true),
            Sense(word: "上方", reading: "かみがた", meaning: "the Kyoto and Osaka region, historically"),
            Sense(word: "上方", reading: "じょうほう", meaning: "upward, the area above"),
            Sense(word: "名代", reading: "なだい", meaning: "famous, well-known"),
            Sense(word: "名代", reading: "みょうだい", meaning: "a representative acting on someone's behalf"),
            Sense(word: "大分", reading: "だいぶ", meaning: "considerably, a lot, quite"),
            Sense(word: "大分", reading: "おおいた", meaning: "Ōita, a prefecture and city in Kyushu"),
            Sense(word: "一寸", reading: "ちょっと", meaning: "a little, a moment, just (一寸待って)"),
            Sense(word: "一寸", reading: "いっすん", meaning: "an old unit of length, about 3 cm; in sayings, a tiny distance (一寸先は闇, 一寸の虫)"),
            Sense(word: "側", reading: "がわ", meaning: "a side, such as one of two parties or one side of something"),
            Sense(word: "側", reading: "そば", meaning: "beside, near, next to"),
            Sense(word: "開ける", reading: "あける", meaning: "open (a door, window, box, a hole)"),
            Sense(word: "開ける", reading: "ひらける", meaning: "open up, develop; be broad-minded, modern"),
            Sense(word: "根本", reading: "こんぽん", meaning: "the root or foundation of an issue; fundamental"),
            Sense(word: "根本", reading: "ねもと", meaning: "the base of a plant, tree or object"),
            Sense(word: "出所", reading: "でどころ", meaning: "the source or origin (of information, money)"),
            Sense(word: "出所", reading: "しゅっしょ", meaning: "release from prison"),
            Sense(word: "黒子", reading: "ほくろ", meaning: "a mole, a small dark spot on the skin"),
            Sense(word: "黒子", reading: "くろこ", meaning: "a stagehand dressed in black in kabuki or puppet theater; someone working behind the scenes"),
            Sense(word: "足跡", reading: "あしあと", meaning: "footprints, tracks"),
            Sense(word: "足跡", reading: "そくせき", meaning: "a person's achievements or legacy"),
            Sense(word: "一味", reading: "いちみ", meaning: "a gang or band of conspirators"),
            Sense(word: "一味", reading: "ひとあじ", meaning: "a touch of flavor (一味違う: a cut above)"),
            Sense(word: "細目", reading: "さいもく", meaning: "detailed items or specifics"),
            Sense(word: "細目", reading: "ほそめ", meaning: "narrowed eyes, eyes slightly open"),
            Sense(word: "一見", reading: "いっけん", meaning: "at first glance, apparently"),
            Sense(word: "一見", reading: "いちげん", meaning: "a first-time customer without an introduction (一見さん)"),
            Sense(word: "自重", reading: "じちょう", meaning: "self-restraint, prudence"),
            Sense(word: "自重", reading: "じじゅう", meaning: "the weight of a vehicle or structure itself"),
            Sense(word: "素振り", reading: "そぶり", meaning: "a sign, manner or behavior that shows feelings"),
            Sense(word: "素振り", reading: "すぶり", meaning: "a practice swing of a bat, sword or racket"),
            Sense(word: "追従", reading: "ついじゅう", meaning: "following, conforming to or imitating others"),
            Sense(word: "追従", reading: "ついしょう", meaning: "flattery, buttering someone up (お追従を言う)"),
            Sense(word: "一端", reading: "いったん", meaning: "one part or one end of something (責任の一端)"),
            Sense(word: "一端", reading: "いっぱし", meaning: "full-fledged; talking or acting like a proper adult or expert (一端の口をきく)"),
            Sense(word: "札", reading: "ふだ", meaning: "a tag, label, card or charm"),
            Sense(word: "札", reading: "さつ", meaning: "a banknote, paper money"),
        ],
        by: \.word
    )
}

/// A reading a word on the homograph list may have, with its meaning.
@_spi(Experiments) public struct RubyReadingChoice: Hashable, Sendable {
    /// The reading of the word as written in the text, in hiragana.
    public let reading: String
    /// What the word means read this way, in English, as the model is told.
    public let meaning: String
}
