import Foundation

/// Shared matching for the rule layers, which replace stretches of an
/// analyzer's segments with readings of their own.
enum RubyRuleSpans {
    /// A stretch of text a rule recognized: where it ends, as a Character
    /// offset, and how it reads.
    struct Match {
        let end: Int
        let reading: String
    }

    /// `segments` with each stretch `match` recognizes replaced by one rule
    /// segment.
    ///
    /// `match` gets the text as Characters, an offset where a segment
    /// starts, and a test for offsets where a stretch may end. A stretch
    /// must start and end on segment boundaries, so it never splits a word
    /// the analyzer found, and may only cover the analyzer's own segments,
    /// so an earlier layer's readings are never overridden.
    static func replacing(
        _ segments: [RubySegment],
        match: (_ text: [Character], _ start: Int, _ isEnd: (Int) -> Bool) -> Match?
    ) -> [RubySegment] {
        let characters = segments.flatMap { Array($0.base) }
        var ends: [Int: Int] = [:] // Character offset of each segment end → its index.
        var starts: [Int] = []
        var offset = 0
        for (index, segment) in segments.enumerated() {
            starts.append(offset)
            offset += segment.base.count
            ends[offset] = index
        }

        var result: [RubySegment] = []
        var index = 0
        while index < segments.count {
            let first = index
            let isEnd = { (end: Int) -> Bool in
                guard let last = ends[end], last >= first else { return false }
                return segments[first...last].allSatisfy { $0.source == .dictionary }
            }
            if segments[index].source == .dictionary,
               let found = match(characters, starts[index], isEnd),
               isEnd(found.end), let last = ends[found.end] {
                result.append(RubySegment(
                    String(characters[starts[index]..<found.end]),
                    reading: found.reading,
                    word: RubySegment.Word(partOfSpeech: .noun, dictionaryForm: nil, attachesToPrevious: false),
                    source: .rule
                ))
                index = last + 1
            } else {
                result.append(segments[index])
                index += 1
            }
        }
        return result
    }
}
