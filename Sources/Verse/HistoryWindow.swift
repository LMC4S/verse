import AppKit
import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published var entries: [History.Entry] = []
    @Published var search = ""
    @Published var copiedID: String?
    @Published var expanded: Set<String> = []

    private var observer: NSObjectProtocol?
    private var copyGeneration = 0

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

    var filtered: [History.Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func copy(_ entry: History.Entry) {
        Paste.copyToClipboard(entry.text)
        copiedID = entry.id
        copyGeneration += 1
        let generation = copyGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if self.copyGeneration == generation { self.copiedID = nil }
        }
    }

    func toggleExpanded(_ entry: History.Entry) {
        if expanded.contains(entry.id) {
            expanded.remove(entry.id)
        } else {
            expanded.insert(entry.id)
        }
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

    var statsLine: String {
        guard !entries.isEmpty else { return "" }
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
        VStack(spacing: 8) {
            WindowHeader(title: "History")
            HStack(spacing: 8) {
                TextField("Search transcripts…", text: $model.search)
                    .fieldChrome()
                Button("Clear All") { model.clearAll() }
                    .buttonStyle(VerseButtonStyle())
                    .disabled(model.entries.isEmpty)
            }
            .padding(.horizontal, 16)

            HStack {
                Text(model.statsLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
                Spacer()
            }

            if model.filtered.isEmpty {
                Text(model.entries.isEmpty ? "No transcripts yet." : "No matches.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filtered) { entry in
                            HistoryRow(
                                entry: entry,
                                copied: model.copiedID == entry.id,
                                expanded: model.expanded.contains(entry.id),
                                onCopy: { model.copy(entry) },
                                onToggleExpand: { model.toggleExpanded(entry) },
                                onDelete: { model.delete(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

/// Click copies (flashes "Copied ✓"), double-click expands, × deletes.
private struct HistoryRow: View {
    let entry: History.Entry
    let copied: Bool
    let expanded: Bool
    var onCopy: () -> Void
    var onToggleExpand: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Hoverable { hovering in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let date = entry.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if !entry.engine.isEmpty {
                        Text(entry.engine == "mlx" ? "MLX" : "OPENAI")
                            .font(.system(size: 9.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Theme.fieldBorder)
                            )
                    }
                    if let ms = entry.durationMs, ms > 0 {
                        Text(String(format: "%d:%02d", ms / 60_000, ms / 1000 % 60))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if copied {
                        Text("Copied ✓")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Button(action: onDelete) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.borderless)
                        .opacity(hovering ? 1 : 0)
                        .help("Delete")
                    }
                }
                Text(entry.text)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                hovering ? Theme.rowHover : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onToggleExpand)
            .onTapGesture(perform: onCopy)
            .contextMenu {
                Button("Copy", action: onCopy)
                Button(expanded ? "Collapse" : "Expand", action: onToggleExpand)
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}
