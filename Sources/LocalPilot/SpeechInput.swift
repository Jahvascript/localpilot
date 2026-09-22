import AVFoundation
import Speech
import PilotCore

@MainActor final class SpeechInput {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var tapped = false
    private var generation = UUID()
    func start(update: @escaping (String) -> Void, ended: @escaping (String?) -> Void) async throws {
        stop()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.supportsOnDeviceRecognition else { throw PilotError.rejected("On-device English speech recognition is unavailable on this Mac. Use typed commands; no cloud fallback is allowed.") }
        let authorization = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        try Task.checkCancellation()
        guard authorization == .authorized else { throw PilotError.rejected("Speech recognition permission was not granted.") }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard microphone else { throw PilotError.rejected("Microphone permission was not granted.") }
        guard recognizer.isAvailable else { throw PilotError.rejected("Local speech recognition is currently unavailable.") }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let token = UUID(); generation = token
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw PilotError.rejected("No usable microphone input.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapped = true
        task = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                guard self.generation == token else { return }
                if let result = result { update(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true {
                    self.stop()
                    ended(error == nil ? nil : "Local recognition stopped. Review the text or use a typed command.")
                }
            }
        }
        do { engine.prepare(); try engine.start() } catch { stop(); throw error }
        timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard self.generation == token else { return }
            self.stop(); ended(nil)
        }
    }
    func stop() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
}
