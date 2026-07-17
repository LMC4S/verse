// Live transcription preview: reads raw PCM (16 kHz, mono, s16le) from stdin
// and prints JSON lines {"type":"volatile"|"final","text":...} as Apple's
// SpeechAnalyzer produces them (macOS 26+). Exits on stdin EOF.
// Built by scripts/build_apple_helper.sh into src/bin/verse-apple-stream.

import AVFoundation
import Foundation
import Speech

func emitLine(_ payload: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
        let line = String(data: data, encoding: .utf8)
    else { return }
    print(line)
    fflush(stdout)
}

guard #available(macOS 26.0, *) else {
    emitLine(["type": "error", "text": "Live preview requires macOS 26 or later."])
    exit(1)
}

let localeID = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : nil

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
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let resultsTask = Task {
            for try await result in transcriber.results {
                emitLine([
                    "type": result.isFinal ? "final" : "volatile",
                    "text": String(result.text.characters),
                ])
            }
        }

        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            )
        else {
            emitLine(["type": "error", "text": "Could not create audio format."])
            return
        }

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputSequence)

        let stdinHandle = FileHandle.standardInput
        while true {
            let data = stdinHandle.availableData
            if data.isEmpty { break }
            let frameCount = AVAudioFrameCount(data.count / 2)
            guard frameCount > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            else { continue }
            buffer.frameLength = frameCount
            data.withUnsafeBytes { raw in
                guard let source = raw.baseAddress,
                    let target = buffer.int16ChannelData?[0]
                else { return }
                memcpy(target, source, Int(frameCount) * 2)
            }
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
        }

        inputBuilder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = try? await resultsTask.value
    } catch {
        emitLine(["type": "error", "text": error.localizedDescription])
    }
}

if #available(macOS 26.0, *) {
    await run()
}
