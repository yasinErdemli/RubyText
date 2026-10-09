/// Japanese in Hangul, as Korean's rules for Japanese words write it: 도쿄,
/// 삿포로, 신분.
///
/// A table can't express it: ん and っ become the final consonant of the
/// syllable before them (しん is 신, さっ 삿), and か, た and ちゃ rows are
/// written without aspiration at the start of a word and with it inside
/// one (こうこう is 고코). Long vowels aren't written, except い after e
/// (せんせい is 센세이).
public struct RubyHangulStyle: RubyTransliterationStyle, CustomStringConvertible {
    public init() {}

    public var description: String { "hangul" }

    public func transliterate(_ phrase: RubyPhrase) -> String {
        var writer = RubyTransliterationWriter(punctuation: RubyTableStyle.latinPunctuation)
        // Whether the next syllable starts a word, where か, た and ちゃ
        // rows aren't aspirated.
        var startsWord = true
        let morae = phrase.morae
        for (index, mora) in morae.enumerated() {
            switch mora.kind {
            case .syllable:
                writer.append(syllable(mora.spoken, startsWord: startsWord))
                startsWord = false
            case .nasal:
                addFinal(Self.nieun, fallback: "ㄴ", to: &writer)
            case .geminate:
                let next = index + 1 < morae.count ? morae[index + 1] : phrase.following
                if next?.kind == .syllable, next?.consonant?.isEmpty == false {
                    addFinal(Self.siot, fallback: "ㅅ", to: &writer)
                }
            case .long:
                if mora.text == "い" {
                    writer.append(syllable("い", startsWord: false))
                }
            case .space:
                writer.space()
                startsWord = true
            case .other:
                writer.write(other: Character(mora.text))
                startsWord = true
            }
        }
        return writer.text
    }

    /// The Hangul syllable for a kana syllable, or each kana's on its own
    /// if Korean has no rule for the pair.
    private func syllable(_ kana: String, startsWord: Bool) -> String {
        if let forms = Self.syllables[kana] {
            return String(startsWord ? forms.first! : forms.last!)
        }
        return kana.compactMap { Self.syllables[String($0)]?.last }.map(String.init).joined()
    }

    /// Adds `final` to the last syllable written, if it's Hangul without
    /// one; otherwise writes `fallback`.
    private func addFinal(_ final: UInt32, fallback: String, to writer: inout RubyTransliterationWriter) {
        guard let last = writer.text.unicodeScalars.last,
              (0xAC00...0xD7A3).contains(last.value),
              (last.value - 0xAC00) % 28 == 0,
              let combined = Unicode.Scalar(last.value + final)
        else {
            writer.append(fallback)
            return
        }
        writer.replaceLast(1, with: String(combined))
    }

    /// The final consonants ㄴ and ㅅ, as offsets within a syllable block.
    private static let nieun: UInt32 = 4
    private static let siot: UInt32 = 19

    /// Each syllable at the start of a word, then inside one, where they
    /// differ: か is 가 first and 카 after.
    private static let syllables: [String: String] = [
        "あ": "아", "い": "이", "う": "우", "え": "에", "お": "오",
        "か": "가카", "き": "기키", "く": "구쿠", "け": "게케", "こ": "고코",
        "さ": "사", "し": "시", "す": "스", "せ": "세", "そ": "소",
        "た": "다타", "ち": "지치", "つ": "쓰", "て": "데테", "と": "도토",
        "な": "나", "に": "니", "ぬ": "누", "ね": "네", "の": "노",
        "は": "하", "ひ": "히", "ふ": "후", "へ": "헤", "ほ": "호",
        "ま": "마", "み": "미", "む": "무", "め": "메", "も": "모",
        "や": "야", "ゆ": "유", "よ": "요",
        "ら": "라", "り": "리", "る": "루", "れ": "레", "ろ": "로",
        "わ": "와", "ゐ": "이", "ゑ": "에", "を": "오",
        "が": "가", "ぎ": "기", "ぐ": "구", "げ": "게", "ご": "고",
        "ざ": "자", "じ": "지", "ず": "즈", "ぜ": "제", "ぞ": "조",
        "だ": "다", "ぢ": "지", "づ": "즈", "で": "데", "ど": "도",
        "ば": "바", "び": "비", "ぶ": "부", "べ": "베", "ぼ": "보",
        "ぱ": "파", "ぴ": "피", "ぷ": "푸", "ぺ": "페", "ぽ": "포",
        "ゔ": "부", "ヵ": "가카", "ヶ": "게케",
        "ぁ": "아", "ぃ": "이", "ぅ": "우", "ぇ": "에", "ぉ": "오",
        "ゃ": "야", "ゅ": "유", "ょ": "요", "ゎ": "와",
        "きゃ": "갸캬", "きゅ": "규큐", "きょ": "교쿄",
        "ぎゃ": "갸", "ぎゅ": "규", "ぎょ": "교",
        "しゃ": "샤", "しゅ": "슈", "しょ": "쇼",
        "じゃ": "자", "じゅ": "주", "じょ": "조",
        "ちゃ": "자차", "ちゅ": "주추", "ちょ": "조초",
        "ぢゃ": "자", "ぢゅ": "주", "ぢょ": "조",
        "にゃ": "냐", "にゅ": "뉴", "にょ": "뇨",
        "ひゃ": "햐", "ひゅ": "휴", "ひょ": "효",
        "びゃ": "뱌", "びゅ": "뷰", "びょ": "뵤",
        "ぴゃ": "퍄", "ぴゅ": "퓨", "ぴょ": "표",
        "みゃ": "먀", "みゅ": "뮤", "みょ": "묘",
        "りゃ": "랴", "りゅ": "류", "りょ": "료",
        "いぇ": "예", "うぃ": "위", "うぇ": "웨", "うぉ": "워",
        "きぇ": "계켸", "ぎぇ": "계", "しぇ": "셰", "じぇ": "제", "ちぇ": "제체", "ぢぇ": "제",
        "にぇ": "녜", "ひぇ": "혜", "びぇ": "볘", "ぴぇ": "폐", "みぇ": "몌", "りぇ": "례",
        "くぁ": "과콰", "くぃ": "귀퀴", "くぇ": "궤퀘", "くぉ": "궈쿼", "くゎ": "과콰",
        "ぐぁ": "과", "ぐぃ": "귀", "ぐぇ": "궤", "ぐぉ": "궈", "ぐゎ": "과",
        "すぃ": "시", "ずぃ": "지",
        "つぁ": "차", "つぃ": "치", "つぇ": "체", "つぉ": "초",
        "てぃ": "티", "でぃ": "디", "とぅ": "투", "どぅ": "두", "てゅ": "튜", "でゅ": "듀",
        "ふぁ": "파", "ふぃ": "피", "ふぇ": "페", "ふぉ": "포", "ふゅ": "퓨",
        "ゔぁ": "바", "ゔぃ": "비", "ゔぇ": "베", "ゔぉ": "보", "ゔゅ": "뷰",
    ]
}
