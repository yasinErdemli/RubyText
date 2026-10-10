import Foundation
import RubyTransliteration

/// Source text with markup removed, plus the words found in it.
///
/// Tokenizing is relatively expensive, so results are cached per markup
/// string, or per segment array, rather than recomputed on every view update.
package final class RubyContent {
    package let string: String
    package let words: [RubyWord]

    /// For text rewritten from other content, such as in hiragana or with
    /// readings in parentheses, the content it was rewritten from. Its
    /// words correspond one to one with this content's.
    package private(set) var original: RubyContent?
    /// For rewritten text, where each UTF-16 offset of the original moved
    /// to, as the start of a range and as its end. The two differ where a
    /// space was put between romaji words.
    private var offsetMap: RubyOffsetMap?
    /// UTF-16 offsets of the spaces kana text was given between phrases
    /// or words, which aren't in the original.
    package private(set) var spaces: [Int] = []
    /// How rewritten text writes its words, if it was rewritten.
    private(set) var rewriteForm: RubyRewriteForm?

    /// Words as a dictionary lists them, for word details: a verb or
    /// adjective with its conjugated endings (生まれ|た), a noun with its
    /// suffixes (田中|さん), or a noun with する as one verb (勉強|し|た).
    /// Particles and other auxiliaries stand alone.
    package private(set) lazy var dictionaryWords: [Range<Int>] = {
        var groups: [(range: Range<Int>, head: RubyPartOfSpeech?)] = []
        for word in words {
            // する after a noun makes a verb, though MeCab tags it independent.
            if let last = groups.last, last.range.upperBound == word.range.lowerBound,
               last.head == .noun, word.dictionaryForm == "する" {
                groups[groups.count - 1] = (last.range.lowerBound..<word.range.upperBound, .verb)
                continue
            }
            if let last = groups.last, last.range.upperBound == word.range.lowerBound,
               word.attachesToPrevious == true, word.partOfSpeech != .particle {
                let continuesInflection = (last.head == .verb || last.head == .adjective)
                    && [.auxiliary, .verb, .adjective].contains(word.partOfSpeech)
                let isSuffix = last.head == .noun && word.partOfSpeech == .noun
                if continuesInflection || isSuffix {
                    groups[groups.count - 1].range = last.range.lowerBound..<word.range.upperBound
                    continue
                }
            }
            groups.append((word.range, word.partOfSpeech))
        }
        return groups.map(\.range)
    }()

    /// Words as Hepburn romaji writes them.
    package var romajiWords: [RubyRomajiWord] { romajiWords(in: .hepburn) }

    private var romajiWordsBySystem: [RubyRomanization: [RubyRomajiWord]] = [:]

    /// Words as romaji in `system` write them, each one annotation.
    /// Verb and adjective endings join their word (読ん|だ → yonda,
    /// し|て → shite, 行き|たい → ikitai); particles, です and helper verbs
    /// stay separate (benkyō shite imasu, kōhī o), except は and も after
    /// another particle (demo, niwa).
    package func romajiWords(in system: RubyRomanization) -> [RubyRomajiWord] {
        if let cached = romajiWordsBySystem[system] { return cached }
        let romajiWords: [RubyRomajiWord] = if let original, let offsetMap {
            // Rewritten text keeps the original's romaji, moved with it.
            rewriteForm != .romaji ? original.romajiWords(in: system).map { RubyRomajiWord(range: offsetMap.range($0.range), text: $0.text) } : []
        } else {
            groupingRomaji(in: system)
        }
        romajiWordsBySystem[system] = romajiWords
        return romajiWords
    }

    /// Words joined into phrases, each written by `system` as one romaji
    /// word.
    private func groupingRomaji(in system: RubyRomanization) -> [RubyRomajiWord] {
        var groups: [(range: Range<Int>, words: [RubyPhrase.Word], isVerbal: Bool, lastWord: RubyWord)] = []
        for word in words {
            guard word.romaji?.isEmpty == false, !word.romajiSources.isEmpty else { continue }
            let base = RubyReadingUnits.substring(of: string, utf16Range: word.range)
            var phraseWords = word.romajiSources.map(\.word)
            if let last = groups.last, last.range.upperBound == word.range.lowerBound,
               Self.joinsRomaji(word, base: base, after: last.lastWord, in: last.range, isVerbal: last.isVerbal, string: string) {
                // The volitional う lengthens the o before it: でしょ|う is
                // deshō, 行こ|う ikō.
                if word.partOfSpeech == .auxiliary, phraseWords.count == 1, phraseWords[0].reading == "う",
                   RubyPhrase(last.words).morae.last?.vowel == "o" {
                    phraseWords[0].pronunciation = "ー"
                }
                groups[groups.count - 1].range = last.range.lowerBound..<word.range.upperBound
                groups[groups.count - 1].words += phraseWords
                groups[groups.count - 1].lastWord = word
                continue
            }
            let isVerbal = [.verb, .adjective, .auxiliary].contains(word.partOfSpeech)
            groups.append((word.range, phraseWords, isVerbal, word))
        }
        return groups.map { group in
            let phrase = RubyPhrase(group.words, following: group.lastWord.romajiSources.last?.next)
            return RubyRomajiWord(range: group.range, text: system.transliterate(phrase))
        }
    }

    /// Whether `word` continues the romaji word before it.
    private static func joinsRomaji(
        _ word: RubyWord,
        base: String,
        after previous: RubyWord,
        in group: Range<Int>,
        isVerbal: Bool,
        string: String
    ) -> Bool {
        // お茶, ご飯 when the analyzer splits the prefix off: ocha, gohan.
        if previous.partOfSpeech == .prefix { return true }
        switch word.partOfSpeech {
        case .auxiliary:
            // The copulas stand alone: takai desu, and だ after a noun or
            // adjective stem (shizuka da). After a verb, だ is the past
            // tense: yonda.
            switch word.dictionaryForm {
            // である is two words too: neko de aru.
            case "です", "ある": return false
            case "だ": return isVerbal && [.verb, .auxiliary].contains(previous.partOfSpeech)
            default: return isVerbal
            }
        case .particle:
            if isVerbal { return conjunctiveParticles.contains(base) }
            // は and も after a particle on its own: dewa, demo, niwa.
            let groupText = RubyReadingUnits.substring(of: string, utf16Range: group)
            return (base == "は" || base == "も") && previous.partOfSpeech == .particle
                && group == previous.range && particlesTakingTopic.contains(groupText)
        case .verb:
            // れる, せる and the like join; helper verbs after て don't.
            return isVerbal && word.attachesToPrevious == true
                && !helperVerbs.contains(word.dictionaryForm ?? base)
        case .adjective:
            // 読みやすい, 食べにくい.
            return isVerbal && word.attachesToPrevious == true && previous.partOfSpeech == .verb
        default:
            return false
        }
    }

    /// Particles joining the verb or adjective before them: 読んで, 飲みながら.
    private static let conjunctiveParticles: Set<String> = ["て", "で", "ば", "たり", "だり", "ながら", "つつ", "ちゃ", "じゃ"]

    /// Particles that は and も join: では, でも, には, とは, へは, からも.
    private static let particlesTakingTopic: Set<String> = ["で", "に", "と", "へ", "から"]

    /// Verbs that follow the て form as separate words: shite imasu,
    /// tabete shimatta, mite miru.
    private static let helperVerbs: Set<String> = [
        "いる", "おる", "ある", "しまう", "くる", "いく", "ゆく", "おく", "みる",
        "あげる", "くれる", "もらう", "いただく", "くださる", "やる",
    ]

    private static let stringCache = NSCache<RubyCacheKey<StringKey>, RubyContent>()
    private static let segmentsCache = NSCache<RubyCacheKey<[RubySegment]>, RubyContent>()

    /// A string analyzed by a particular analyzer, or by none.
    private struct StringKey: Hashable {
        let string: RubyString
        let analyzer: AnyHashable?

        init(string: RubyString, analyzer: (any RubyAnalyzer)?) {
            self.string = string
            self.analyzer = analyzer.map { AnyHashable($0) }
        }
    }

    /// Content for `markup`, with readings `analyzer` finds wherever the
    /// markup doesn't supply them. Without an analyzer, only the markup's
    /// readings show.
    package static func content(for markup: String, analyzer: (any RubyAnalyzer)?) -> RubyContent {
        content(for: RubyString(markup: markup), analyzer: analyzer)
    }

    /// Content for `string`, analyzed as one text, with the readings it
    /// gives and those `analyzer` finds for the rest. Its unannotated text
    /// isn't annotated.
    package static func content(for string: RubyString, analyzer: (any RubyAnalyzer)?) -> RubyContent {
        let key = RubyCacheKey(StringKey(string: string, analyzer: analyzer))
        if let cached = stringCache.object(forKey: key) { return cached }
        let (text, manual, unannotated) = parse(string)
        let segments = Self.unannotated(segments(in: text, analyzer: analyzer), in: unannotated)
        let content = RubyContent(string: text, manual: manual, segments: segments)
        stringCache.setObject(content, forKey: key)
        return content
    }

    private static let modelCache = NSCache<RubyCacheKey<ModelKey>, RubyContent>()

    /// Forgets content with the model's readings, so it's asked again.
    package static func forgetModelReadings() {
        modelCache.removeAllObjects()
    }

    /// A string analyzed by a particular analyzer, with a chooser's readings.
    private struct ModelKey: Hashable {
        let string: StringKey
        let chooser: AnyHashable
    }

    /// Content for `markup` with the model layer on top; see
    /// `content(for:analyzer:chooser:onEachReading:)` for strings.
    package static func content(
        for markup: String,
        analyzer: (any RubyAnalyzer)?,
        chooser: some RubyReadingChooser,
        onEachReading: ((RubyContent) async -> Void)? = nil
    ) async -> RubyContent {
        await content(for: RubyString(markup: markup), analyzer: analyzer, chooser: chooser, onEachReading: onEachReading)
    }

    /// Content for `string` with the model layer on top: words whose
    /// reading depends on their meaning, such as 辛い or 人気, read the way
    /// `chooser` judges the sentence means them.
    ///
    /// The same as `content(for:analyzer:)` where the text has no such
    /// words or the chooser can't answer. Only readings change, so words
    /// cover the same ranges in both.
    ///
    /// - Parameter onEachReading: Called with the content so far each time
    ///   an answer changes a reading, to show readings as they come.
    package static func content(
        for string: RubyString,
        analyzer: (any RubyAnalyzer)?,
        chooser: some RubyReadingChooser,
        onEachReading: ((RubyContent) async -> Void)? = nil
    ) async -> RubyContent {
        let key = RubyCacheKey(ModelKey(
            string: StringKey(string: string, analyzer: analyzer),
            chooser: AnyHashable(chooser)
        ))
        if let cached = modelCache.object(forKey: key) { return cached }
        let (text, manual, unannotated) = parse(string)
        let segments = Self.unannotated(Self.segments(in: text, analyzer: analyzer), in: unannotated)
        let onChange: (([RubySegment]) async -> Void)? = onEachReading.map { update in
            { segments in await update(RubyContent(string: text, manual: manual, segments: segments)) }
        }
        let chosen = await RubyModelReadings.apply(
            to: segments,
            excluding: manual.map(\.range) + unannotated,
            chooser: chooser,
            onChange: onChange
        )
        // Unchanged, possibly because the chooser couldn't answer yet, so
        // only changed content is cached.
        guard chosen != segments else { return Self.content(for: string, analyzer: analyzer) }
        let content = RubyContent(string: text, manual: manual, segments: chosen)
        modelCache.setObject(content, forKey: key)
        return content
    }

    /// Content built directly from segments the caller supplies, with no
    /// analysis: `RubyText(segments:)`'s way of showing an app's own data.
    package static func content(for segments: [RubySegment]) -> RubyContent {
        let key = RubyCacheKey(segments)
        if let cached = segmentsCache.object(forKey: key) { return cached }
        let content = RubyContent(segments: segments)
        segmentsCache.setObject(content, forKey: key)
        return content
    }

    /// The text of `markup` without its markup, and a word for each
    /// manual reading in it.
    package static func parse(_ markup: String) -> (string: String, manual: [RubyWord]) {
        let (string, manual, _) = parse(RubyString(markup: markup))
        return (string, manual)
    }

    /// The text of `string`, a word for each reading it gives, and the
    /// UTF-16 ranges of its unannotated text.
    package static func parse(_ string: RubyString) -> (string: String, manual: [RubyWord], unannotated: [Range<Int>]) {
        var text = ""
        var manual: [RubyWord] = []
        var unannotated: [Range<Int>] = []
        for piece in string.pieces {
            switch piece {
            case .markup(let markup):
                for part in RubyMarkup.parse(markup) {
                    if let reading = part.reading {
                        manual.append(RubyReadings.word(manualBase: part.base, reading: reading, offset: text.utf16.count))
                    }
                    text += part.base
                }
            case .text(let plain):
                text += plain
            case .ruby(let base, let reading):
                manual.append(RubyReadings.word(manualBase: base, reading: reading, offset: text.utf16.count))
                text += base
            case .unannotated(let plain):
                let start = text.utf16.count
                text += plain
                unannotated.append(start..<text.utf16.count)
            }
        }
        return (text, manual, unannotated)
    }

    /// `segments` without readings or grammar where they touch `ranges`,
    /// so text there gets no words: no furigana, romaji, or details.
    private static func unannotated(_ segments: [RubySegment], in ranges: [Range<Int>]) -> [RubySegment] {
        guard !ranges.isEmpty else { return segments }
        var offset = 0
        return segments.map { segment in
            let range = offset..<(offset + segment.base.utf16.count)
            offset = range.upperBound
            guard ranges.contains(where: { $0.overlaps(range) }) else { return segment }
            return RubySegment(segment.base, source: .dictionary)
        }
    }

    /// Content for `string` from the automatic layers' `segments`, which
    /// cover all of it, with `manual` words on top.
    ///
    /// The segments come from the whole string so manual readings don't
    /// cut words apart: 行き in "{行|い}きたい" still reads "iki".
    private init(string: String, manual: [RubyWord], segments: [RubySegment]) {
        self.string = string
        let automatic = Self.words(from: segments)
        guard !manual.isEmpty else {
            words = automatic
            return
        }

        var words: [RubyWord] = []
        var pending = manual[...]
        for word in automatic {
            // Emit manual words that come before this token.
            while let next = pending.first, next.range.upperBound <= word.range.lowerBound {
                words.append(next)
                pending = pending.dropFirst()
            }
            let overlapping = manual.filter { $0.range.overlaps(word.range) }
            if overlapping.isEmpty {
                words.append(word)
            } else if overlapping.contains(where: { $0.range.contains(word.range.lowerBound) && word.range.upperBound <= $0.range.upperBound }) {
                // Token lies inside a manual segment; the manual word replaces it.
                continue
            } else {
                // Token straddles manual segments: use manual furigana wherever
                // the author supplied one. If the segments cover the whole
                // token ({一|いち}{日|にち}), their readings also replace the
                // token's romaji, which may disagree (一日 → tsuitachi).
                let furigana = word.furigana.filter { reading in
                    !overlapping.contains { $0.range.overlaps(reading.range) }
                } + overlapping.flatMap(\.furigana)
                let coversToken = (overlapping.first?.range.lowerBound ?? .max) <= word.range.lowerBound
                    && (overlapping.last?.range.upperBound ?? .min) >= word.range.upperBound
                    && zip(overlapping, overlapping.dropFirst()).allSatisfy { $0.range.upperBound == $1.range.lowerBound }
                words.append(RubyWord(
                    range: word.range,
                    furigana: furigana.sorted { $0.range.lowerBound < $1.range.lowerBound },
                    romaji: coversToken ? overlapping.compactMap(\.romaji).joined() : word.romaji,
                    romajiSources: coversToken ? overlapping.flatMap(\.romajiSources) : word.romajiSources,
                    attachesToPrevious: word.attachesToPrevious,
                    partOfSpeech: word.partOfSpeech,
                    dictionaryForm: word.dictionaryForm,
                    source: .manual
                ))
                // Those manual words are now part of this token.
                pending = pending.drop { $0.range.overlaps(word.range) }
            }
        }
        words += pending

        // Manual words take their grammar from the token they replace, so
        // they're grouped and colored like the rest of the text.
        self.words = words.sorted { $0.range.lowerBound < $1.range.lowerBound }.map { word in
            guard word.partOfSpeech == nil,
                  let token = automatic.first(where: { $0.range.overlaps(word.range) })
            else { return word }
            var word = word
            word.attachesToPrevious = word.attachesToPrevious ?? token.attachesToPrevious
            word.partOfSpeech = token.partOfSpeech
            word.dictionaryForm = token.range == word.range ? token.dictionaryForm : nil
            return word
        }
    }

    private init(segments: [RubySegment]) {
        self.string = segments.map(\.base).joined()
        self.words = Self.words(from: segments)
    }

    /// `original` rewritten as `string` in `form`, its words moved
    /// through `offsets`, with `spaces` put between phrases or words.
    /// Readings are part of the rewritten text, so the words have no
    /// furigana; they keep their romaji unless the text is romaji already.
    init(rewriting original: RubyContent, as string: String, form: RubyRewriteForm, offsets: RubyOffsetMap, spaces: [Int]) {
        self.string = string
        let keepsRomaji = form != .romaji
        words = original.words.map { word in
            RubyWord(
                range: offsets.range(word.range),
                furigana: [],
                romaji: keepsRomaji ? word.romaji : nil,
                romajiSources: keepsRomaji ? word.romajiSources : [],
                attachesToPrevious: word.attachesToPrevious,
                partOfSpeech: word.partOfSpeech,
                dictionaryForm: word.dictionaryForm,
                source: word.source
            )
        }
        self.original = original
        offsetMap = offsets
        self.spaces = spaces
        rewriteForm = form
        dictionaryWords = original.dictionaryWords.map(offsets.range)
    }

    /// The text this content was rewritten from, or its own.
    package var sourceString: String { original?.string ?? string }

    /// Where `range` of the original text is in this text; the same range
    /// for content that wasn't rewritten.
    package func range(fromOriginal range: Range<Int>) -> Range<Int> {
        offsetMap?.range(range) ?? range
    }

    /// Where the original text's UTF-16 `offset` is in this text, as the
    /// end of what comes before it.
    package func offset(fromOriginal offset: Int) -> Int {
        offsetMap?.end(offset) ?? offset
    }

    /// Segments for `text` from the automatic layers, in priority order:
    /// rules, then the analyzer's dictionary readings. Each rule only
    /// replaces segments still read by the analyzer. Without an analyzer,
    /// one segment with no reading covers the text.
    package static func segments(in text: String, analyzer: (any RubyAnalyzer)?) -> [RubySegment] {
        guard let analyzer else {
            return text.isEmpty ? [] : [RubySegment(text, source: .dictionary)]
        }
        var segments = analyzer.segments(in: text).map(Self.normalized)
        segments = RubyPhraseReadings.applyPhrases(to: segments)
        segments = RubyNumberReadings.apply(to: segments)
        segments = RubyPhraseReadings.applySuffixes(to: segments)
        segments = RubyPhraseReadings.applyNan(to: segments)
        return segments
    }

    /// `segment` from an analyzer, the way the rest of RubyText expects
    /// it: readings in hiragana, and a word whenever there's something to
    /// read, even if the analyzer knows nothing of its grammar. Only
    /// segments with nothing to say, such as punctuation, stay plain.
    /// Readings an analyzer finds are the dictionary's, even if it left
    /// `source` at `.manual`, the default for readings you write.
    private static func normalized(_ segment: RubySegment) -> RubySegment {
        var segment = segment
        if segment.source == .manual {
            segment.source = .dictionary
        }
        segment.reading = segment.reading.flatMap { $0.isEmpty ? nil : RubyKana.hiragana($0) }
        segment.pronunciation = segment.pronunciation.flatMap { $0.isEmpty ? nil : RubyKana.hiragana($0) }
        if segment.word == nil, segment.reading != nil || segment.base.contains(where: { $0.isLetter || $0.isNumber }) {
            segment.word = RubySegment.Word()
        }
        return segment
    }

    /// Converts segments into ranged words, computing furigana and romaji
    /// from each segment's reading. A segment only from the dictionary
    /// layer with no grammar, such as punctuation, doesn't become a word;
    /// every other segment does, even without a reading.
    package static func words(from segments: [RubySegment]) -> [RubyWord] {
        var words: [RubyWord] = []
        var offset = 0
        for (index, segment) in segments.enumerated() {
            defer { offset += segment.base.utf16.count }
            guard segment.source != .dictionary || segment.word != nil else { continue }
            let range = offset..<(offset + segment.base.utf16.count)
            let furigana = segment.reading.map {
                RubyReadings.furigana(base: segment.base, reading: $0, offset: offset, force: segment.source != .dictionary)
            } ?? []
            // The next word's reading resolves a final っ (入っ|た → itta).
            let next = index + 1 < segments.count ? segments[index + 1].reading : nil
            let role: RubyPhrase.Word.Role = if segment.word?.isProperNoun == true {
                .properNoun
            } else if segment.word?.partOfSpeech == .particle {
                .particle
            } else {
                .other
            }
            let source = segment.reading.map {
                RubyRomajiSource(
                    surface: segment.base,
                    reading: $0,
                    pronunciation: segment.pronunciation ?? particlePronunciation[segment.base],
                    role: role,
                    next: next,
                    breaks: segment.romajiBreaks
                )
            }
            words.append(RubyWord(
                range: range,
                furigana: furigana,
                romaji: source?.romaji(in: .hepburn),
                romajiSources: source.map { [$0] } ?? [],
                attachesToPrevious: segment.word?.attachesToPrevious,
                partOfSpeech: segment.word?.partOfSpeech,
                dictionaryForm: segment.word?.dictionaryForm,
                source: segment.source
            ))
        }
        return words
    }
}

/// A word as romaji writes it, which may join several analyzer words.
package struct RubyRomajiWord: Hashable, Sendable {
    /// UTF-16 range in the text.
    package let range: Range<Int>
    package let text: String
}

/// Particles spoken differently from their spelling, for segments whose
/// analyzer didn't say so.
private let particlePronunciation: [String: String] = ["は": "わ", "へ": "え"]

/// Wraps a value as a key for `RubyContent`'s caches. `NSCache` keys must be
/// objects, and value types aren't.
package final class RubyCacheKey<Value: Hashable>: NSObject {
    let value: Value

    package init(_ value: Value) {
        self.value = value
    }

    override package var hash: Int { value.hashValue }

    override package func isEqual(_ object: Any?) -> Bool {
        (object as? RubyCacheKey<Value>)?.value == value
    }
}
