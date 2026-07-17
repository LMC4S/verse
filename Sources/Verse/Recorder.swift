import AVFoundation
import Foundation

/// Records the microphone to a 16 kHz mono WAV via AVAudioEngine — one format
/// every engine accepts (OpenAI, MLX, Apple) — while exposing a live level
/// for the meter and, optionally, converted buffers for the live preview.
final class Recorder {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var url: URL?
    private var startedAt: Date?
    private var currentLevel: Double = 0

    /// Receives 16 kHz mono int16 buffers on the audio thread (live preview).
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    var isRecording: Bool { engine.isRunning }

    static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verse-\(UUID().uuidString).wav")
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "Verse", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input is available."
            ])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw NSError(domain: "Verse", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not prepare the audio converter."
            ])
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: Self.targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        self.url = url
        self.file = file
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Meter level from the raw input.
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += samples[index] * samples[index]
            }
            let rms = sqrt(sum / Float(buffer.frameLength))
            currentLevel = Double(min(1, pow(rms, 0.5) * 1.6))
        }

        // Convert to 16 kHz mono int16, write to the WAV, feed the preview.
        guard let converter else { return }
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat, frameCapacity: capacity
        ) else { return }

        var consumed = false
        let status = converter.convert(to: out, error: nil) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return }
        try? file?.write(from: out)
        onBuffer?(out)
    }

    func level() -> Double {
        currentLevel
    }

    func elapsed() -> TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onBuffer = nil
        converter = nil
        file = nil // closes the WAV
        currentLevel = 0
    }

    func stop() -> (url: URL, durationMs: Int)? {
        guard let url, let startedAt else { return nil }
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        teardown()
        self.url = nil
        self.startedAt = nil
        return (url, durationMs)
    }

    func cancel() {
        teardown()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        startedAt = nil
    }
}
