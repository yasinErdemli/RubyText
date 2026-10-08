import Foundation

/// Source text with markup removed, plus the words found in it.
///
/// Tokenizing is relatively expensive, so results are cached per markup
/// string, or per segment array, rather than recomputed on every view update.
package final class RubyContent {
    package let string: String
    package let words: [RubyWord]

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

    /// Words as romaji writes them, each one annotation below the text.
    /// Verb and adjective endings join their word (読ん|だ → yonda,
    /// し|て → shite, 行き|たい → ikitai); particles, です and helper verbs
    /// stay separate (benkyō shite imasu, kōhī o), except は and も after
    /// another particle (demo, niwa).
    package private(set) lazy var romajiWords: [RubyRomajiWord] = {
        var groups: [(range: Range<Int>, text: String, isVerbal: Bool, lastWord: RubyWord)] = []
        for word in words {
            guard let romaji = word.romaji, !romaji.isEmpty else { continue }
            let base = RubyReadingUnits.substring(of: string, utf16Range: word.range)
            if let last = groups.last, last.range.upperBound == word.range.lowerBound,
               Self.joinsRomaji(word, base: base, after: last.lastWord, in: last.range, isVerbal: last.isVerbal, string: string) {
                groups[groups.count - 1].range = last.range.lowerBound..<word.range.upperBound
                // The volitional う lengthens the o before it: でしょ|う is
                // deshō, 行こ|う ikō.
                if word.partOfSpeech == .auxiliary, romaji == "u", last.text.hasSuffix("o") {
                    groups[groups.count - 1].text.removeLast()
                    groups[groups.count - 1].text += "ō"
                } else {
                    groups[groups.count - 1].text += romaji
                }
                groups[groups.count - 1].lastWord = word
                continue
            }
            let isVerbal = [.verb, .adjective, .auxiliary].contains(word.partOfSpeech)
            groups.append((word.range, romaji, isVerbal, word))
        }
        return groups.map { RubyRomajiWord(range: $0.range, text: $0.text) }
    }()

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

    private static let markupCache = NSCache<RubyCacheKey<MarkupKey>, RubyContent>()
    private static let segmentsCache = NSCache<RubyCacheKey<[RubySegment]>, RubyContent>()

    /// Markup analyzed by a particular analyzer.
    private struct MarkupKey: Hashable {
        let markup: String
        let analyzer: AnyHashable
    }

    /// Content for `markup`, with readings `analyzer` finds wherever the
    /// markup doesn't supply them.
    package static func content(
        for markup: String,
        analyzer: any RubyAnalyzer = RubyMeCabAnalyzer.shared
    ) -> RubyContent {
        let key = RubyCacheKey(MarkupKey(markup: markup, analyzer: AnyHashable(analyzer)))
        if let cached = markupCache.object(forKey: key) { return cached }
        let content = RubyContent(markup: markup, analyzer: analyzer)
        markupCache.setObject(content, forKey: key)
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

    private init(markup: String, analyzer: any RubyAnalyzer) {
        var string = ""
        var manual: [RubyWord] = []
        for piece in RubyMarkup.parse(markup) {
            if let reading = piece.reading {
                manual.append(RubyReadings.word(manualBase: piece.base, reading: reading, offset: string.utf16.count))
            }
            string += piece.base
        }
        self.string = string

        // Tokenize the whole string so manual readings don't cut words apart
        // (行き in "{行|い}きたい" still reads "iki"), then apply them on top.
        let automatic = Self.words(from: Self.segments(in: string, analyzer: analyzer))
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

    /// Segments for `text` from the automatic layers, in priority order:
    /// rules, then the analyzer's dictionary readings. Each rule only
    /// replaces segments still read by the analyzer.
    package static func segments(in text: String, analyzer: any RubyAnalyzer) -> [RubySegment] {
        var segments = analyzer.segments(in: text)
        segments = RubyPhraseReadings.applyPhrases(to: segments)
        segments = RubyNumberReadings.apply(to: segments)
        segments = RubyPhraseReadings.applySuffixes(to: segments)
        return segments
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
            let romaji = segment.reading.map {
                RubyRomaji.hepburn($0, pronunciation: segment.pronunciation ?? particlePronunciation[segment.base], next: next)
            }
            words.append(RubyWord(
                range: range,
                furigana: furigana,
                romaji: romaji,
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
private final class RubyCacheKey<Value: Hashable>: NSObject {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    override var hash: Int { value.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? RubyCacheKey<Value>)?.value == value
    }
}
