import Foundation

enum TranscriberError: LocalizedError {
    case noAPIKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "Save an OpenAI API key first."
        case .badResponse(let message): message
        }
    }
}

enum Transcriber {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let model = "whisper-1"

    static func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.noAPIKey }

        let boundary = "verse-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        func field(_ string: String) { body.append(Data(string.utf8)) }
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        field("Content-Type: audio/m4a\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        field("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = ((json["error"] as? [String: Any])?["message"] as? String)
                ?? "OpenAI returned HTTP \(status)."
            throw TranscriberError.badResponse(message)
        }
        guard let text = json["text"] as? String else {
            throw TranscriberError.badResponse("OpenAI response did not include transcript text.")
        }
        return text
    }
}
