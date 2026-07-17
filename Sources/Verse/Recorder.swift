import AVFoundation
import Foundation

/// Records the microphone to a temporary AAC file (16 kHz mono — small
/// uploads, plenty for speech) with metering for the level display.
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    var isRecording: Bool { recorder?.isRecording ?? false }

    static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verse-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "Verse", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not start the microphone."
            ])
        }
        self.recorder = recorder
        startedAt = Date()
    }

    /// Normalized 0…1 loudness for the meter.
    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0) // -160…0 dB
        let floor: Float = -50
        return Double(max(0, min(1, (decibels - floor) / -floor)))
    }

    func elapsed() -> TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    func stop() -> (url: URL, durationMs: Int)? {
        guard let recorder, let startedAt else { return nil }
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        recorder.stop()
        let url = recorder.url
        self.recorder = nil
        self.startedAt = nil
        return (url, durationMs)
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        startedAt = nil
    }
}
