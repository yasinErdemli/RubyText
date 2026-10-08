import Testing

/// A word whose reading is easy to get wrong, in a sentence that decides it.
struct BenchmarkCase: Sendable, CustomTestStringConvertible {
    enum Kind: String, CaseIterable, Sendable {
        /// Dates, times, and amounts, which need their own rules.
        case number
        /// Counters, whose sound changes with the number (一本, 三本, 六本).
        case counter
        /// Words read as a whole rather than kanji by kanji (今日, 大人).
        case special
        /// Words whose reading depends on their meaning in context.
        case meaning
        /// Fixed phrases and compounds whose reading changes when joined
        /// (一日中, 本棚, 人々).
        case phrase
        /// Names of people and places.
        case name
        /// Everyday words, kept as a guard against regressions.
        case control
    }

    let sentence: String
    let word: String
    /// Correct readings of `word` in hiragana, the usual one first.
    let readings: [String]
    let kind: Kind
    /// The wrong reading the default analyzer gives today, or `nil` if it
    /// reads the word correctly. Known errors don't fail the tests; a
    /// different result does, so fixes and regressions both show up.
    let mecab: String?

    var testDescription: String { "\(word) → \(readings[0])" }
}

private func c(
    _ word: String,
    _ readings: String...,
    in sentence: String,
    _ kind: BenchmarkCase.Kind,
    mecab: String? = nil
) -> BenchmarkCase {
    BenchmarkCase(sentence: sentence, word: word, readings: readings, kind: kind, mecab: mecab)
}

/// The accuracy benchmark: the roadmap's test sentences, then cases grouped
/// by kind.
let readingBenchmark: [BenchmarkCase] = roadmapCases + numberCases + counterCases + specialCases
    + meaningCases + phraseCases + nameCases + controlCases

// MARK: Roadmap sentences

private let date = "2025年3月16日"
private let stress = "侍の魂と志を胸に、暁の湖で雷を待つ。"
private let market = "三月一日、大家さんと人気のない早朝の魚市場へ行き、辛い生物を一日中食べたら寒気がした。"
private let shop = "あの方は一枚上手で、気に入った店でも今日は止めておくと言った。"

private let roadmapCases = [
    c(date, "にせんにじゅうごねんさんがつじゅうろくにち", in: date, .number),

    // The layout stress test.
    c("侍", "さむらい", in: stress, .control),
    c("魂", "たましい", in: stress, .control),
    c("志", "こころざし", in: stress, .control),
    c("胸", "むね", in: stress, .control),
    c("暁", "あかつき", in: stress, .control),
    c("湖", "みずうみ", in: stress, .control),
    c("雷", "かみなり", in: stress, .control),
    c("待つ", "まつ", in: stress, .control),

    // The twelve traps.
    c("三月一日", "さんがつついたち", in: market, .number),
    c("大家さん", "おおやさん", in: market, .phrase),
    c("人気", "ひとけ", in: market, .meaning, mecab: "にんき"),
    c("魚市場", "うおいちば", in: market, .phrase),
    c("辛い", "からい", in: market, .meaning, mecab: "つらい"),
    c("生物", "なまもの", in: market, .meaning, mecab: "せいぶつ"),
    c("一日中", "いちにちじゅう", in: market, .phrase),
    c("寒気", "さむけ", in: market, .phrase),
    c("あの方", "あのかた", in: shop, .meaning, mecab: "あのほう"),
    c("一枚上手", "いちまいうわて", in: shop, .phrase),
    c("気に入った", "きにいった", in: shop, .phrase),
    c("止めておく", "やめておく", in: shop, .meaning, mecab: "とめておく"),
]

// MARK: Numbers

private let numberCases = [
    // Irregular days of the month.
    c("一月一日", "いちがつついたち", in: "一月一日は元日です。", .number),
    c("四月二日", "しがつふつか", in: "四月二日に入学した。", .number),
    c("三日前", "みっかまえ", in: "三日前に着いた。", .number),
    c("五月五日", "ごがついつか", in: "五月五日はこどもの日です。", .number),
    c("六日間", "むいかかん", in: "六日間旅行した。", .number),
    c("七月七日", "しちがつなのか", in: "七月七日に会いましょう。", .number),
    c("八日", "ようか", in: "八日に会いましょう。", .number),
    c("九月九日", "くがつここのか", in: "九月九日は重陽の節句です。", .number),
    c("十日", "とおか", in: "十日に試験がある。", .number),
    c("十四日", "じゅうよっか", in: "十四日まで休みです。", .number),
    c("十七日", "じゅうしちにち", in: "十七日に会議がある。", .number),
    c("二十日", "はつか", in: "二十日に給料が出る。", .number),
    c("二十四日", "にじゅうよっか", in: "二十四日に帰る。", .number),
    c("二十九日", "にじゅうくにち", in: "二十九日が締め切りです。", .number),

    // Months and hours.
    c("４月", "しがつ", in: "４月に卒業した。", .number),
    c("3時", "さんじ", in: "3時に起きた。", .number),
    c("4時", "よじ", in: "4時に会おう。", .number),
    c("七時", "しちじ", "ななじ", in: "七時に起きる。", .number),
    c("九時", "くじ", in: "九時に始まる。", .number),
    c("十分後", "じっぷんご", "じゅっぷんご", in: "十分後に出発します。", .number),
    c("十分間", "じっぷんかん", "じゅっぷんかん", in: "十分間待った。", .number),

    // Years and amounts.
    c("2026年", "にせんにじゅうろくねん", in: "2026年に発売された。", .number),
    c("100円", "ひゃくえん", in: "100円を払った。", .number),
    c("三百円", "さんびゃくえん", in: "三百円です。", .number),
    c("六百人", "ろっぴゃくにん", in: "六百人が来た。", .number),
    c("三千円", "さんぜんえん", in: "三千円でした。", .number),
    c("一万円札", "いちまんえんさつ", in: "一万円札で払った。", .number),
]

// MARK: Counters

private let counterCases = [
    c("一人", "ひとり", in: "一人で行った。", .counter),
    c("二人", "ふたり", in: "二人で話した。", .counter),
    c("三人", "さんにん", in: "三人の子供がいる。", .counter),
    c("四人家族", "よにんかぞく", in: "四人家族です。", .counter),
    c("一本", "いっぽん", in: "鉛筆を一本ください。", .counter),
    c("三本", "さんぼん", in: "ビールを三本飲んだ。", .counter),
    c("六本", "ろっぽん", in: "木が六本ある。", .counter),
    c("一匹", "いっぴき", in: "猫が一匹いる。", .counter),
    c("三匹", "さんびき", in: "犬が三匹いる。", .counter),
    c("一杯", "いっぱい", in: "水を一杯ください。", .counter),
    c("三杯", "さんばい", in: "ご飯を三杯食べた。", .counter),
    c("三階", "さんがい", "さんかい", in: "三階に住んでいる。", .counter),
    c("一回", "いっかい", in: "もう一回やってみる。", .counter),
    c("八歳", "はっさい", "はちさい", in: "娘は八歳です。", .counter),
    c("二十歳", "はたち", "にじゅっさい", "にじゅうさい", in: "二十歳になった。", .counter),
    c("一つ", "ひとつ", in: "りんごを一つ食べた。", .counter),
    c("九つ", "ここのつ", in: "箱が九つある。", .counter),
    c("一分", "いっぷん", in: "一分待ってください。", .counter),
    c("五分", "ごふん", in: "駅まで五分で着く。", .counter),
    c("一個", "いっこ", in: "卵を一個割った。", .counter),
    c("一冊", "いっさつ", in: "本を一冊買った。", .counter),
    c("三足", "さんぞく", in: "靴を三足買った。", .counter),
]

// MARK: Special readings

private let specialCases = [
    c("今日", "きょう", in: "今日は暑い。", .special),
    c("明日", "あした", "あす", in: "明日は雨だ。", .special),
    c("昨日", "きのう", in: "昨日は休みだった。", .special),
    c("今朝", "けさ", in: "今朝は早く起きた。", .special),
    c("今年", "ことし", in: "今年の夏は暑い。", .special),
    c("一昨日", "おととい", "いっさくじつ", in: "一昨日の夜に電話した。", .special),
    c("明後日", "あさって", "みょうごにち", in: "明後日に出発する。", .special),
    c("大人", "おとな", in: "大人になったら分かる。", .special),
    c("眼鏡", "めがね", in: "眼鏡をかけている。", .special),
    c("時計", "とけい", in: "時計が止まった。", .special),
    c("果物", "くだもの", in: "果物が好きです。", .special),
    c("土産", "みやげ", in: "お土産を買った。", .special),
    c("部屋", "へや", in: "部屋を掃除した。", .special),
    c("景色", "けしき", in: "山の景色がきれいだ。", .special),
    c("七夕", "たなばた", in: "七夕に願い事をした。", .special),
    c("八百屋", "やおや", in: "八百屋で野菜を買った。", .special),
    c("相撲", "すもう", in: "相撲を見に行った。", .special),
    c("浴衣", "ゆかた", in: "浴衣を着て祭りに行った。", .special),
    c("足袋", "たび", in: "足袋を履いた。", .special),
    c("田舎", "いなか", in: "田舎に帰る。", .special),
    c("迷子", "まいご", in: "子供が迷子になった。", .special),
    c("息子", "むすこ", in: "息子は大学生です。", .special),
    c("お母さん", "おかあさん", in: "お母さんに電話した。", .special),
    c("お父さん", "おとうさん", in: "お父さんは会社員です。", .special),
    c("お姉さん", "おねえさん", in: "お姉さんと買い物に行った。", .special),
    c("お兄さん", "おにいさん", in: "お兄さんは背が高い。", .special),
    c("叔父", "おじ", in: "叔父が遊びに来た。", .special),
    c("博士", "はかせ", "はくし", in: "博士が研究している。", .special),
    c("白髪", "しらが", "はくはつ", in: "白髪が増えた。", .special),
    c("真面目", "まじめ", in: "彼は真面目な人だ。", .special),
    c("意気地", "いくじ", in: "意気地がない。", .special),
    c("風邪", "かぜ", in: "風邪をひいた。", .special),
    c("梅雨", "つゆ", "ばいう", in: "梅雨が明けた。", .special),
    c("五月雨", "さみだれ", in: "五月雨が降り続く。", .special),
    c("時雨", "しぐれ", in: "時雨が降ってきた。", .special),
    c("吹雪", "ふぶき", in: "吹雪で電車が止まった。", .special),
    c("雪崩", "なだれ", in: "雪崩が起きた。", .special),
    c("竹刀", "しない", in: "竹刀で練習する。", .special),
    c("小豆", "あずき", in: "小豆を煮た。", .special),
    c("素人", "しろうと", in: "私は素人です。", .special),
    c("玄人", "くろうと", in: "玄人の技だ。", .special),
    c("仲人", "なこうど", in: "仲人を頼んだ。", .special),
    c("為替", "かわせ", in: "為替が変動している。", .special),
    c("二日酔い", "ふつかよい", in: "二日酔いで頭が痛い。", .special),
    c("紅葉狩り", "もみじがり", in: "紅葉狩りに行った。", .special),
]

// MARK: Meaning

private let meaningCases = [
    // Pairs: the same spelling read differently in different sentences.
    c("人気", "にんき", in: "人気のある店に行った。", .meaning),
    c("辛い", "つらい", in: "別れは辛い。", .meaning),
    c("生物", "せいぶつ", in: "生物の授業がある。", .meaning),
    c("方", "ほう", in: "こちらの方が安い。", .meaning),
    c("止める", "とめる", in: "車を止める。", .meaning),
    c("行った", "おこなった", in: "会議を行った。", .meaning),
    c("行った", "いった", in: "学校に行った。", .meaning),
    c("十分", "じゅうぶん", in: "昨日は十分休んだ。", .meaning),
    c("上手", "じょうず", in: "歌が上手だ。", .meaning),
    c("下手", "へた", in: "絵が下手だ。", .meaning),
    c("大家", "たいか", in: "書道の大家として知られる。", .meaning, mecab: "おおや"),
    c("一日", "いちにち", in: "一日休んだ。", .meaning),
    c("今日", "こんにち", in: "今日の日本経済は厳しい。", .meaning, mecab: "きょう"),
    c("色紙", "いろがみ", in: "色紙で鶴を折った。", .meaning),
    c("色紙", "しきし", in: "色紙にサインをもらった。", .meaning, mecab: "いろがみ"),
    c("寒気", "かんき", in: "寒気が南下している。", .meaning, mecab: "さむけ"),
    c("最中", "さいちゅう", in: "食事の最中に電話が鳴った。", .meaning),
    c("最中", "もなか", in: "和菓子の最中を食べた。", .meaning, mecab: "さいちゅう"),
    c("何", "なに", in: "何を食べますか。", .meaning),
    c("何", "なん", in: "これは何ですか。", .meaning, mecab: "なに"),
    c("開く", "あく", "ひらく", in: "ドアが開く。", .meaning),
    c("開く", "ひらく", in: "会議を開く。", .meaning),
    c("空いた", "すいた", in: "お腹が空いた。", .meaning, mecab: "あいた"),
    c("空いた", "あいた", in: "席が空いた。", .meaning),
    c("角", "かど", in: "次の角を曲がる。", .meaning, mecab: "かく"),
    c("角", "つの", in: "牛の角は硬い。", .meaning, mecab: "かく"),
    c("後で", "あとで", in: "後で電話する。", .meaning),
    c("入る", "はいる", in: "部屋に入る。", .meaning),
    c("日本", "にほん", "にっぽん", in: "日本に住んでいる。", .meaning),
]

// MARK: Phrases and compounds

private let phraseCases = [
    c("世界中", "せかいじゅう", in: "世界中で人気がある。", .phrase),
    c("一年中", "いちねんじゅう", in: "ここは一年中暖かい。", .phrase),
    c("今日中", "きょうじゅう", in: "今日中に終わらせる。", .phrase),
    c("会議中", "かいぎちゅう", in: "今は会議中です。", .phrase),
    c("授業中", "じゅぎょうちゅう", in: "授業中は静かにしてください。", .phrase),
    c("一生懸命", "いっしょうけんめい", in: "一生懸命働いた。", .phrase),
    c("居心地", "いごこち", in: "この部屋は居心地がいい。", .phrase),
    c("合図", "あいず", in: "手で合図した。", .phrase),
    c("本棚", "ほんだな", in: "本棚に本を並べた。", .phrase),
    c("雨傘", "あまがさ", in: "雨傘を持っていく。", .phrase),
    c("雨雲", "あまぐも", in: "雨雲が近づいている。", .phrase),
    c("船便", "ふなびん", "せんびん", in: "荷物を船便で送った。", .phrase),
    c("酒屋", "さかや", in: "酒屋で日本酒を買った。", .phrase),
    c("手作り", "てづくり", in: "手作りのケーキです。", .phrase),
    c("物語", "ものがたり", in: "古い物語を読んだ。", .phrase),
    c("日帰り", "ひがえり", in: "日帰りで温泉に行った。", .phrase),
    c("人々", "ひとびと", in: "多くの人々が集まった。", .phrase),
    c("時々", "ときどき", in: "時々映画を見る。", .phrase),
    c("色々", "いろいろ", in: "色々な国に行った。", .phrase),
    c("我々", "われわれ", in: "我々は反対する。", .phrase),
    c("何時", "なんじ", in: "今何時ですか。", .phrase),
    c("何人", "なんにん", in: "何人いますか。", .phrase),

    // 中: じゅう "throughout" after time and places, ちゅう "during".
    c("一晩中", "ひとばんじゅう", in: "一晩中起きていた。", .phrase),
    c("今年中", "ことしじゅう", in: "今年中に完成させたい。", .phrase),
    c("明日中", "あしたじゅう", "あすじゅう", in: "明日中に返事します。", .phrase),
    c("日本中", "にほんじゅう", "にっぽんじゅう", in: "日本中で話題になった。", .phrase),
    c("体中", "からだじゅう", in: "体中が痛い。", .phrase),
    c("国中", "くにじゅう", in: "国中が喜んだ。", .phrase),
    c("部屋中", "へやじゅう", in: "部屋中を探した。", .phrase),
    c("学校中", "がっこうじゅう", in: "学校中に知れ渡った。", .phrase),
    c("午前中", "ごぜんちゅう", in: "午前中は忙しい。", .phrase),
    c("今週中", "こんしゅうちゅう", "こんしゅうじゅう", in: "今週中に連絡します。", .phrase),
    c("今月中", "こんげつちゅう", in: "今月中に払います。", .phrase),
    c("仕事中", "しごとちゅう", in: "今は仕事中です。", .phrase),
    c("工事中", "こうじちゅう", in: "この道は工事中です。", .phrase),
    c("中", "なか", in: "箱の中を見た。", .phrase),
    c("途中", "とちゅう", in: "帰る途中で寄った。", .phrase),
    c("背中", "せなか", in: "背中が痛い。", .phrase),

    // Idioms, several with numerals the number rules must leave alone.
    c("一足先", "ひとあしさき", in: "一足先に帰ります。", .phrase),
    c("一通り", "ひととおり", in: "一通り説明した。", .phrase),
    c("七転八倒", "しちてんばっとう", in: "痛みで七転八倒した。", .phrase),
    c("一人旅", "ひとりたび", in: "一人旅が好きだ。", .phrase),
    c("一人暮らし", "ひとりぐらし", in: "一人暮らしを始めた。", .phrase),
    c("一人前", "いちにんまえ", in: "やっと一人前になった。", .phrase),
    c("一人一人", "ひとりひとり", in: "一人一人に聞いた。", .phrase),
    c("二人きり", "ふたりきり", in: "二人きりで話した。", .phrase),
    c("人一倍", "ひといちばい", in: "人一倍努力した。", .phrase),
    c("十人十色", "じゅうにんといろ", in: "好みは十人十色だ。", .phrase),
    c("一石二鳥", "いっせきにちょう", in: "それは一石二鳥だ。", .phrase),
    c("三日坊主", "みっかぼうず", in: "日記は三日坊主で終わった。", .phrase),
    c("一期一会", "いちごいちえ", in: "一期一会を大切にする。", .phrase),
    c("八百長", "やおちょう", in: "八百長の疑いがある。", .phrase),
    c("二枚目", "にまいめ", in: "彼は二枚目だ。", .phrase),
    c("一番乗り", "いちばんのり", in: "一番乗りで到着した。", .phrase),
    c("四六時中", "しろくじちゅう", in: "四六時中考えている。", .phrase),
]

// MARK: Names

private let nameCases = [
    c("田中", "たなか", in: "田中さんに会った。", .name),
    c("佐藤", "さとう", in: "佐藤さんは先生です。", .name),
    c("鈴木", "すずき", in: "鈴木さんから電話があった。", .name),
    c("山田太郎", "やまだたろう", in: "山田太郎と申します。", .name),
    c("花子", "はなこ", in: "花子は学生です。", .name),
    c("長谷川", "はせがわ", in: "長谷川さんが来た。", .name),
    c("服部", "はっとり", in: "服部さんは忍者の子孫だ。", .name),
    c("東海林", "しょうじ", "とうかいりん", in: "東海林さんは営業部です。", .name),
    c("夏目漱石", "なつめそうせき", in: "夏目漱石の小説を読んだ。", .name),
    c("東京", "とうきょう", in: "東京に住んでいる。", .name),
    c("大阪", "おおさか", in: "大阪で生まれた。", .name),
    c("京都", "きょうと", in: "京都を観光した。", .name),
    c("北海道", "ほっかいどう", in: "北海道は寒い。", .name),
    c("富士山", "ふじさん", in: "富士山に登った。", .name),
    c("渋谷", "しぶや", in: "渋谷で待ち合わせた。", .name),
    c("新宿", "しんじゅく", in: "新宿駅で降りた。", .name),
    c("秋葉原", "あきはばら", in: "秋葉原で買い物した。", .name),
    c("御茶ノ水", "おちゃのみず", in: "御茶ノ水の大学に通う。", .name),
    c("名古屋", "なごや", in: "名古屋に出張した。", .name),
    c("神戸", "こうべ", in: "神戸の夜景がきれいだ。", .name),
    c("札幌", "さっぽろ", in: "札幌で雪祭りを見た。", .name),
    c("奈良", "なら", in: "奈良で鹿を見た。", .name),
]

// MARK: Controls

private let controlCases = [
    c("吾輩", "わがはい", in: "吾輩は猫である。", .control),
    c("猫", "ねこ", in: "吾輩は猫である。", .control),
    c("生まれた", "うまれた", in: "どこで生まれたかとんと見当がつかぬ。", .control),
    c("見当", "けんとう", in: "どこで生まれたかとんと見当がつかぬ。", .control),
    c("勉強", "べんきょう", in: "日本語を勉強しています。", .control),
    c("学校", "がっこう", in: "学校に通っている。", .control),
    c("先生", "せんせい", in: "先生に質問した。", .control),
    c("電車", "でんしゃ", in: "電車が遅れた。", .control),
    c("新聞", "しんぶん", in: "毎朝新聞を読む。", .control),
    c("図書館", "としょかん", in: "図書館で本を借りた。", .control),
    c("食べる", "たべる", in: "ご飯を食べる。", .control),
    c("飲み物", "のみもの", in: "飲み物を買った。", .control),
    c("美しい", "うつくしい", in: "美しい花が咲いた。", .control),
    c("静か", "しずか", in: "図書館は静かだ。", .control),
    c("新幹線", "しんかんせん", in: "新幹線で京都に行った。", .control),
    c("天気", "てんき", in: "天気がいい。", .control),
    c("病院", "びょういん", in: "病院に行った。", .control),
    c("経済", "けいざい", in: "経済が成長している。", .control),
    c("自転車", "じてんしゃ", in: "自転車で通勤する。", .control),
    c("携帯電話", "けいたいでんわ", in: "携帯電話を忘れた。", .control),
    // Katakana in a word with kanji keeps its ー (the ＡＩ bug: ー became い).
    c("生ビール", "なまびーる", in: "生ビールを一杯ください。", .control, mecab: "なまびいる"),
]
