import Accelerate
import AVFoundation
import Foundation

/// WebAudio-style spectrum analyser (the Electron panel used AnalyserNode):
/// 512-point FFT, Blackman window, 0.75 smoothing, -100…-30 dB range.
/// Written from the audio thread, read from the UI timer.
final class SpectrumAnalyzer {
    static let fftSize = 512
    static let binCount = fftSize / 2

    private let fftSetup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: fftSize)
    private var latest = [Float](repeating: 0, count: fftSize)
    private var smoothed = [Float](repeating: 0, count: binCount)
    private let lock = NSLock()

    init() {
        vDSP_blkman_window(&window, vDSP_Length(Self.fftSize), 0)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Feed the raw microphone tap buffer (float, device sample rate) — the
    /// same signal WebAudio's AnalyserNode taps in v1.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        if count >= Self.fftSize {
            for index in 0..<Self.fftSize {
                latest[index] = floatData[count - Self.fftSize + index]
            }
        } else {
            latest.removeFirst(count)
            for index in 0..<count {
                latest.append(floatData[index])
            }
        }

        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP_vmul(latest, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        var real = [Float](repeating: 0, count: Self.binCount)
        var imag = [Float](repeating: 0, count: Self.binCount)
        for index in 0..<Self.binCount {
            real[index] = windowed[2 * index]
            imag[index] = windowed[2 * index + 1]
        }
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(
                    realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!
                )
                vDSP_fft_zrip(fftSetup, &split, 1, 9, FFTDirection(FFT_FORWARD))
            }
        }
        for index in 0..<Self.binCount {
            let magnitude = sqrt(real[index] * real[index] + imag[index] * imag[index])
                / Float(Self.fftSize)
            // Snappier than v1's 0.75 because we update ~12×/s, not 60×/s;
            // this matches the same ~60 ms time constant.
            smoothed[index] = 0.45 * smoothed[index] + 0.55 * magnitude
        }
    }

    private var peakDb: Float = -55

    /// Per-bar levels 0…1, sampling the lower 70% of the spectrum like v1 —
    /// but normalized against a tracked recent peak (fast rise, ~10 dB/s
    /// decay) so the meter uses its full height at any mic gain.
    func barLevels(_ barCount: Int) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let dbs = (0..<barCount).map { barIndex -> Float in
            let bin = Int(Float(barIndex) / Float(barCount) * Float(Self.binCount) * 0.7)
            return 20 * log10(max(smoothed[bin], 1e-7))
        }
        peakDb = max(dbs.max() ?? -100, peakDb - 0.35, -55)
        let floorDb = peakDb - 42
        return dbs.map { Double(min(1, max(0, ($0 - floorDb) / 42))) }
    }

    func reset() {
        lock.lock()
        latest = [Float](repeating: 0, count: Self.fftSize)
        smoothed = [Float](repeating: 0, count: Self.binCount)
        peakDb = -55
        lock.unlock()
    }
}

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
    let spectrum = SpectrumAnalyzer()

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
        spectrum.append(buffer)

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
        spectrum.reset()
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
