import AVFoundation
import Foundation
import Speech

/// Apple's on-device speech models (SpeechAnalyzer, macOS 26+). The Electron
/// app shells out to helper binaries for this; here it runs in-process.
enum AppleSpeech {
    static func resolveLocale(_ requested: Locale) async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.first { $0.identifier(.bcp47) == requested.identifier(.bcp47) }
            ?? supported.first { $0.language.languageCode == requested.language.languageCode }
            ?? Locale(identifier: "en-US")
    }

    /// Batch transcription of a recorded file.
    static func transcribe(fileURL: URL) async throws -> String {
        let locale = await resolveLocale(Locale.current)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: fileURL)

        let collector = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Live transcript preview: feed microphone buffers, receive volatile/final
/// text as the analyzer produces it. Port of v1's verse-apple-stream helper.
final class AppleLiveTranscriber {
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Starts the analyzer; onText is called off the main thread.
    func start(onText: @escaping @Sendable (_ isFinal: Bool, _ text: String) -> Void) async -> Bool {
        do {
            let locale = await AppleSpeech.resolveLocale(Locale.current)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                try await request.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        onText(result.isFinal, String(result.text.characters))
                    }
                } catch {
                    // Preview is best effort; recording continues without it.
                }
            }
            let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await analyzer.start(inputSequence: sequence)
            self.analyzer = analyzer
            self.inputBuilder = builder
            return true
        } catch {
            return false
        }
    }

    /// Called from the audio tap thread with 16 kHz mono buffers.
    func feed(_ buffer: AVAudioPCMBuffer) {
        inputBuilder?.yield(AnalyzerInput(buffer: buffer))
    }

    func stop() {
        inputBuilder?.finish()
        inputBuilder = nil
        let analyzer = analyzer
        self.analyzer = nil
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        }
    }
}
