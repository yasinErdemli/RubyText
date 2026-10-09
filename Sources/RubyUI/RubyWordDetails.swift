import RubyCore
import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// An action to perform when someone taps a word in a `RubyText`.
struct RubyWordTapAction {
    let handler: (RubyWordInfo) -> Void

    func callAsFunction(_ word: RubyWordInfo) {
        handler(word)
    }
}

extension EnvironmentValues {
    /// Whether tapping a word in a `RubyText` shows its details.
    @Entry var rubyShowsWordDetails = false
    /// What to do when someone taps a word in a `RubyText`, if anything.
    @Entry var rubyWordTapAction: RubyWordTapAction? = nil
    /// Definitions for word details, if any.
    @Entry var rubyDictionary: RubyDictionary? = nil
}

extension View {
    /// Shows a word's reading, dictionary form, part of speech, and JLPT
    /// level in a popover when someone taps it in a `RubyText`, with
    /// buttons to hear it and look it up in the system dictionary.
    public func rubyWordDetails(_ isEnabled: Bool = true) -> some View {
        environment(\.rubyShowsWordDetails, isEnabled)
    }

    /// Performs `action` when someone taps a word in a `RubyText`, such as
    /// to show your own word card or save the word to a study list.
    public func onRubyWordTap(perform action: @escaping (RubyWordInfo) -> Void) -> some View {
        environment(\.rubyWordTapAction, RubyWordTapAction(handler: action))
    }

    /// Sets the dictionary that word details in this hierarchy show
    /// definitions from. Set it once, near the root of your app, with a
    /// database your app bundles:
    ///
    ///     let dictionary = RubyDictionary(
    ///         url: Bundle.main.url(forResource: "jmdict", withExtension: "sqlite")!
    ///     )
    ///
    ///     ContentView()
    ///         .rubyDictionary(dictionary)
    ///
    /// Without one, word details show the reading, part of speech and JLPT
    /// level, but no definitions.
    public func rubyDictionary(_ dictionary: RubyDictionary?) -> some View {
        environment(\.rubyDictionary, dictionary)
    }
}

/// The card `rubyWordDetails()` shows for a tapped word.
public struct RubyWordDetailView: View {
    public let word: RubyWordInfo

    /// Dictionary entries for the word, best match first. Looked up when
    /// the card is created, which takes a millisecond or two, so the card
    /// has its final size when the popover opens.
    @State private var entries: [RubyDictionary.Entry]

    /// Creates a card for `word`, with definitions from `dictionary` if
    /// there is one.
    public init(word: RubyWordInfo, dictionary: RubyDictionary? = nil) {
        self.word = word
        _entries = State(initialValue: dictionary?.entries(for: word) ?? [])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    // The word as written with its reading above, however
                    // the text it was tapped in is written.
                    RubyText(verbatim: word.text)
                        .font(.largeTitle)
                        .rubyStyle()
                        .rubyFuriganaScript(.hiragana)
                        .rubyFuriganaPosition(.above)
                        .rubyTranscription(nil)
                        .textSelection(.enabled)
                    if !word.romaji.isEmpty {
                        Text(verbatim: word.romaji)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 16)
                Button("Listen", systemImage: "speaker.wave.2.fill") {
                    RubyWordSpeaker.shared.speak(word.text)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if word.reading != word.text {
                    row("Reading") { Text(verbatim: word.reading) }
                }
                if let dictionaryForm = word.dictionaryForm {
                    row("Dictionary form") { Text(verbatim: dictionaryForm) }
                }
                // The dictionary's part of speech is more detailed than
                // MeCab's (Ichidan verb, Intransitive), so prefer it.
                if let partsOfSpeech = entries.first?.senses.first?.partsOfSpeech, !partsOfSpeech.isEmpty {
                    row("Part of speech") { Text(partsOfSpeech.joined(separator: ", ")) }
                } else if let partOfSpeech = word.partOfSpeech, partOfSpeech != .other {
                    row("Part of speech") { Text(partOfSpeech.localizedName) }
                }
                if let level = word.jlptLevel {
                    row("JLPT") { RubyJLPTBadge(level: level) }
                }
            }
            .font(.subheadline)

            if let entry = entries.first {
                meanings(of: entry, others: entries.dropFirst())
            }

            if word.kanji.count > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kanji")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Array(word.kanji.enumerated()), id: \.offset) { _, kanji in
                            VStack(spacing: 4) {
                                Text(String(kanji.character)).font(.title2)
                                if let level = kanji.level {
                                    RubyJLPTBadge(level: level)
                                } else {
                                    Text("Beyond N1")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                        }
                    }
                }
            }

            #if canImport(UIKit)
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: lookUpTerm) {
                Button("Look Up “\(lookUpTerm)”", systemImage: "character.book.closed") {
                    RubySystemDictionary.show(lookUpTerm)
                }
            }
            #endif

            if !entries.isEmpty {
                Text(RubyDictionary.credit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, alignment: .leading)
    }

    /// The best entry's senses, numbered, then other entries spelled the
    /// same way. The first sense's part of speech is in the row above, so a
    /// sense only shows its own when it differs from the one before.
    private func meanings(of entry: RubyDictionary.Entry, others: ArraySlice<RubyDictionary.Entry>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meaning")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { index, sense in
                VStack(alignment: .leading, spacing: 2) {
                    if index > 0, sense.partsOfSpeech != entry.senses[index - 1].partsOfSpeech {
                        Text(sense.partsOfSpeech.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if entry.senses.count > 1 {
                            Text(verbatim: "\(index + 1).")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(sense.glosses.joined(separator: "; "))
                    }
                }
            }
            if !others.isEmpty {
                Text("Also: \(others.map { Self.summary(of: $0) }.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    /// An entry in one line: 生【なま】 raw.
    private static func summary(of entry: RubyDictionary.Entry) -> String {
        let reading = entry.readings.first ?? ""
        let headword = entry.spellings.first.map { "\($0)【\(reading)】" } ?? reading
        return [headword, entry.senses.first?.glosses.first].compactMap { $0 }.joined(separator: " ")
    }

    /// The form a dictionary lists the word under.
    private var lookUpTerm: String {
        word.dictionaryForm ?? word.text
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value()
        }
    }
}

/// A small colored label for a JLPT level, in the `jlpt` word colors.
struct RubyJLPTBadge: View {
    let level: RubyJLPTLevel

    var body: some View {
        let color = RubyWordColors.defaultJLPTColors[level] ?? .gray
        Text(verbatim: level.name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

/// Speaks single words for word details, with the best Japanese voice.
@MainActor
final class RubyWordSpeaker {
    static let shared = RubyWordSpeaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = RubyReader.japaneseVoices.first ?? AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }
}

#if canImport(UIKit)
/// Shows the system dictionary's definition of a term.
///
/// `UIReferenceLibraryViewController` manages its own presentation and
/// closes itself right away when wrapped in a SwiftUI sheet, so it's
/// presented directly, over whatever is frontmost, such as the word card.
@MainActor
enum RubySystemDictionary {
    static func show(_ term: String) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(UIReferenceLibraryViewController(term: term), animated: true)
    }
}
#endif

#Preview("Word details") {
    // RubyUI doesn't include a dictionary, so the reading comes from markup.
    let content = RubyContent.content(for: "{見当|けんとう}", analyzer: nil)
    RubyWordDetailView(word: .info(for: content.words[0].range, in: content))
}
