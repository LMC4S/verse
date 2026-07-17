import Foundation

/// Local transcription via mlx-whisper, sharing the venv that Verse 1.x
/// installs under ~/Library/Application Support/Verse/local-mlx.
enum MLX {
    private static var devRoot: URL {
        AppSettings.dataDirectory.appendingPathComponent("local-mlx")
    }

    private static var v1Root: URL {
        AppSettings.v1Directory.appendingPathComponent("local-mlx")
    }

    /// Reuses the ~1 GB engine that Verse 1.x installed, if present —
    /// transcription only reads and executes it. Fresh installs go to the
    /// dev directory so v1's copy is never written to.
    static var isSharedWithV1: Bool {
        !FileManager.default.fileExists(
            atPath: devRoot.appendingPathComponent("venv/bin/python3").path
        ) && FileManager.default.fileExists(
            atPath: v1Root.appendingPathComponent("venv/bin/python3").path
        )
    }

    static var root: URL {
        isSharedWithV1 ? v1Root : devRoot
    }

    static var venvPython: URL {
        root.appendingPathComponent("venv/bin/python3")
    }

    static var scriptURL: URL? {
        Bundle.main.url(forResource: "local_mlx_transcribe", withExtension: "py")
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        env["HF_HOME"] = root.appendingPathComponent("huggingface").path
        env["HF_HUB_CACHE"] = root.appendingPathComponent("huggingface/hub").path
        env["XDG_CACHE_HOME"] = root.appendingPathComponent("cache").path
        return env
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let out = String(
                    data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                let err = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: TranscriberError.badResponse(
                        message.isEmpty
                            ? "\(executable) exited with \(process.terminationStatus)."
                            : message
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func isInstalled() async -> Bool {
        guard FileManager.default.fileExists(atPath: venvPython.path) else { return false }
        return (try? await run(venvPython.path, ["-c", "import mlx_whisper"])) != nil
    }

    private static func findSystemPython() async throws -> String {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/usr/bin/python3",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            if (try? await run(candidate, ["--version"])) != nil { return candidate }
        }
        throw TranscriberError.badResponse("Could not find python3.")
    }

    static func install(progress: @escaping @Sendable (String) -> Void) async throws {
        guard !isSharedWithV1 else { return } // never write into v1's engine
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: venvPython.path) {
            progress("Creating Python environment…")
            let python = try await findSystemPython()
            try await run(python, ["-m", "venv", root.appendingPathComponent("venv").path])
        }
        progress("Updating pip…")
        try await run(venvPython.path, ["-m", "pip", "install", "--upgrade", "pip"])
        progress("Installing mlx-whisper…")
        try await run(venvPython.path, ["-m", "pip", "install", "--upgrade", "mlx-whisper"])
    }

    static func remove() throws {
        guard !isSharedWithV1 else { return } // v1's engine is managed by v1
        try FileManager.default.removeItem(at: devRoot)
    }

    static func transcribe(fileURL: URL, model: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            throw TranscriberError.badResponse(
                "Install Local MLX in Settings before using the local engine."
            )
        }
        guard let script = scriptURL else {
            throw TranscriberError.badResponse("The Local MLX helper script is missing.")
        }
        let output = try await run(
            venvPython.path, [script.path, fileURL.path, "--model", model]
        )
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw TranscriberError.badResponse("MLX response did not include transcript text.")
        }
        return text
    }
}
