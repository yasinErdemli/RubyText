// Precomputes speech-recognition segments for a narration recording, so an
// app can align it to text without on-device recognition.
//
// Run from the repository root:
//   swift run align-narration path/to/natsume.m4a
//
// Writes natsume.segments.json next to the recording and prints the
// recognized segments. RubyReader reads that file when it plays the
// recording, instead of recognizing it on device.
import Foundation
import RubyUI

@main
struct AlignNarration {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            print("usage: align-narration <recording>")
            exit(1)
        }
        let url = URL(fileURLWithPath: arguments[1])
        do {
            let segments = try await RubyNarrationAligner.transcribe(url)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let output = RubyNarrationAligner.segmentsURL(for: url)
            try encoder.encode(segments).write(to: output)
            print("Wrote \(segments.count) segments to \(output.path)")
            for segment in segments {
                print(String(format: "  %.2f–%.2f  ", segment.start, segment.end) + segment.text)
            }
        } catch {
            print("error:", error.localizedDescription)
            exit(1)
        }
    }
}
