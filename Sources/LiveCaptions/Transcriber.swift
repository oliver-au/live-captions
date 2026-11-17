import AVFoundation
import Speech

/// Turns a stream of audio buffers into caption text using Apple's on-device
/// SpeechAnalyzer + SpeechTranscriber (macOS 26+). Nothing leaves the Mac.
final class Transcriber: @unchecked Sendable {
    typealias ResultHandler = @MainActor (_ text: String, _ isFinal: Bool) -> Void
    typealias StatusHandler = @MainActor (_ status: String?) -> Void

    private let onResult: ResultHandler
    private let onStatus: StatusHandler

    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // Only touched from the audio callback queue of the owning source.
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(onResult: @escaping ResultHandler, onStatus: @escaping StatusHandler) {
        self.onResult = onResult
        self.onStatus = onStatus
    }

    func start(locale requested: Locale = Locale(identifier: "en-US")) async throws {
        guard SpeechTranscriber.isAvailable else { throw CaptionError.speechUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw CaptionError.localeUnsupported(requested.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // volatileResults: show words while they're still being recognized.
            // fastResults: lower latency, closer to Windows Live Captions.
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        // Download the on-device model the first time (handled by macOS).
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await onStatus("Downloading the English speech model…")
            try await request.downloadAndInstall()
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        inputContinuation = continuation

        let onResult = self.onResult
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await onResult(text, result.isFinal)
                }
            } catch {
                NSLog("LiveCaptions: transcriber results ended: \(error)")
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        await onStatus(nil)
    }

    /// Feed audio. Called on the audio source's callback queue.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation else { return }
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        resultsTask?.cancel()
        resultsTask = nil
        converter = nil
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = analyzerFormat, buffer.frameLength > 0 else { return nil }
        if buffer.format == target { return buffer }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
            converter?.downmix = true
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            NSLog("LiveCaptions: audio conversion failed: \(String(describing: error))")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }
}

enum CaptionError: LocalizedError {
    case speechUnavailable
    case localeUnsupported(String)
    case audioSetup(String)

    var errorDescription: String? {
        switch self {
        case .speechUnavailable: "On-device speech recognition isn't available on this Mac."
        case .localeUnsupported(let id): "The speech model doesn't support \(id)."
        case .audioSetup(let message): message
        }
    }
}
