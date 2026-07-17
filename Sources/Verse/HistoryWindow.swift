import AppKit
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var entries: [History.Entry] = []
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .verseHistoryChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        entries = History.list()
    }

    func delete(_ entry: History.Entry) {
        History.delete(id: entry.id)
    }

    func clearAll() {
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all transcripts?"
        alert.informativeText =
            "This permanently deletes all \(entries.count) entries from history."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            History.clear()
        }
    }

    var statsLine: String? {
        guard !entries.isEmpty else { return nil }
        var parts = ["\(entries.count) transcript\(entries.count == 1 ? "" : "s")"]
        let totalMs = entries.compactMap(\.durationMs).reduce(0, +)
        if totalMs > 0 {
            let minutes = Double(totalMs) / 60_000
            parts.append(minutes < 1 ? "<1 min" : "\(Int(minutes.rounded())) min")
            let openAIMs = entries.filter { $0.engine == "openai" }
                .compactMap(\.durationMs).reduce(0, +)
            if openAIMs > 0 {
                let cost = Double(openAIMs) / 60_000 * History.openAICostPerMinute
                parts.append(String(format: "~$%.2f OpenAI", cost))
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        VStack(spacing: 0) {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "No transcripts yet",
                    systemImage: "quote.opening",
                    description: Text("Recordings you transcribe will appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.entries) { entry in
                        HistoryRow(entry: entry) {
                            Paste.copyToClipboard(entry.text)
                        } onDelete: {
                            model.delete(entry)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack {
                Text(model.statsLine ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { model.clearAll() }
                    .controlSize(.small)
                    .disabled(model.entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct HistoryRow: View {
    let entry: History.Entry
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(4)
                    .textSelection(.enabled)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var caption: String {
        var parts: [String] = []
        if let date = entry.createdAt {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if !entry.engine.isEmpty {
            parts.append(entry.engine == "mlx" ? "Local MLX" : "OpenAI")
        }
        if let ms = entry.durationMs, ms > 0 {
            parts.append(String(format: "%d:%02d", ms / 60_000, ms / 1000 % 60))
        }
        return parts.joined(separator: " · ")
    }
}
