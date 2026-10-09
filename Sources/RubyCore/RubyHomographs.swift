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
