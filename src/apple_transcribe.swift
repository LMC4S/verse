// Transcribes an audio file with Apple's on-device speech models
// (SpeechAnalyzer, macOS 26+). Prints JSON {"text": ...} or {"error": ...}.
// Built by scripts/build_apple_helper.sh into src/bin/verse-apple-transcribe.

import AVFoundation
import Foundation
import Speech

func emit(_ payload: [String: String]) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    print(String(data: data, encoding: .utf8)!)
    exit(payload["error"] == nil ? 0 : 1)
}

guard CommandLine.arguments.count >= 2 else {
    emit(["error": "Usage: verse-apple-transcribe <audio-file> [locale]"])
}
let audioURL = URL(fileURLWithPath: CommandLine.arguments[1])
let localeID = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil

guard #available(macOS 26.0, *) else {
    emit(["error": "Apple Speech engine requires macOS 26 or later."])
}

@available(macOS 26.0, *)
func run() async {
    do {
        let requested = localeID.map(Locale.init(identifier:)) ?? Locale.current
        let supported = await SpeechTranscriber.supportedLocales
        let locale =
            supported.first(where: { $0.identifier(.bcp47) == requested.identifier(.bcp47) })
            ?? supported.first(where: {
                $0.language.languageCode == requested.language.languageCode
            })
            ?? Locale(identifier: "en-US")

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)

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

        let text = try await collector.value
        emit(["text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
    } catch {
        emit(["error": "\(error.localizedDescription)"])
    }
}

if #available(macOS 26.0, *) {
    await run()
}
