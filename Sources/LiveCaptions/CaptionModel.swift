import Foundation
import Observation

enum CaptionSource {
    case system
    case microphone
}

/// Holds the finalized transcript plus the in-progress ("volatile") text of each source.
@Observable
final class CaptionModel {
    struct Segment {
        let source: CaptionSource
        let text: String
        let date: Date
    }

    /// Finalized sentences, oldest first. Capped so memory stays small however long it runs.
    private(set) var segments: [Segment] = []
    /// About 3–5 hours of continuous speech, well under 1 MB.
    static let maxSegments = 2_000
    private(set) var volatileSystem = ""
    private(set) var volatileMicrophone = ""
    /// Shown when there is no caption text yet, e.g. "Downloading speech model…".
    var status: String?
    var isRunning = false
    /// Increments on every caption change, so the view knows when to follow new text.
    private(set) var revision = 0

    func update(source: CaptionSource, text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        revision += 1
        if isFinal {
            if !trimmed.isEmpty {
                segments.append(Segment(source: source, text: trimmed, date: Date()))
                if segments.count > Self.maxSegments {
                    // Drop in batches so we don't shift the whole array on every sentence.
                    segments.removeFirst(segments.count - Self.maxSegments + 100)
                }
            }
            setVolatile("", for: source)
        } else {
            setVolatile(trimmed, for: source)
        }
    }

    func clearVolatile(for source: CaptionSource) {
        setVolatile("", for: source)
    }

    private func setVolatile(_ text: String, for source: CaptionSource) {
        switch source {
        case .system: volatileSystem = text
        case .microphone: volatileMicrophone = text
        }
    }

    var isEmpty: Bool {
        segments.isEmpty && volatileSystem.isEmpty && volatileMicrophone.isEmpty
    }

    /// Recent caption text for display. Finalized text is followed by in-progress text;
    /// a new line starts whenever the speaker source changes, and mic lines get a "Me:" label.
    func displayRuns(maxSegments: Int = 300) -> [(text: String, kind: RunKind)] {
        var runs: [(String, RunKind)] = []
        var lastSource: CaptionSource?

        func append(_ text: String, source: CaptionSource, volatile: Bool) {
            if source != lastSource {
                if lastSource != nil { runs.append(("\n", .final)) }
                if source == .microphone { runs.append(("Me: ", .speakerLabel)) }
                lastSource = source
            } else {
                runs.append((" ", .final))
            }
            runs.append((text, volatile ? .volatile : .final))
        }

        for segment in segments.suffix(maxSegments) {
            append(segment.text, source: segment.source, volatile: false)
        }
        if !volatileSystem.isEmpty { append(volatileSystem, source: .system, volatile: true) }
        if !volatileMicrophone.isEmpty { append(volatileMicrophone, source: .microphone, volatile: true) }
        return runs
    }

    enum RunKind {
        case final
        case volatile
        case speakerLabel
    }

    /// Full transcript with timestamps, for "Copy transcript".
    var transcript: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return segments.map { segment in
            let speaker = segment.source == .microphone ? "Me: " : ""
            return "[\(formatter.string(from: segment.date))] \(speaker)\(segment.text)"
        }.joined(separator: "\n")
    }
}
