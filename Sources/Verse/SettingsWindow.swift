import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hasKey: Bool
    @Published var newKey = ""
    @Published var engine: String
    @Published var mlxModel: String
    @Published var autoPaste: Bool
    @Published var shortcut: String
    @Published var launchAtLogin: Bool
    @Published var mlxInstalled = false
    @Published var mlxBusy = false
    @Published var mlxStatus = "Checking…"
    @Published var shortcutRecording = false
    @Published var shortcutFailed = false

    /// Set by AppDelegate; re-registers the global hotkey, returns success.
    var applyShortcut: (String) -> Bool = { _ in false }
    private var keyMonitor: Any?

    init() {
        let settings = AppSettings.load()
        hasKey = !settings.apiKey.isEmpty
        engine = settings.engine
        mlxModel = settings.mlxModel
        autoPaste = settings.autoPaste
        shortcut = settings.shortcut
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func saveKey() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        AppSettings.save(["apiKey": key])
        newKey = ""
        hasKey = true
    }

    func saveEngine() {
        AppSettings.save(["engine": engine])
    }

    func saveMlxModel() {
        let model = mlxModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        AppSettings.save(["mlxModel": model])
    }

    func saveAutoPaste() {
        AppSettings.save(["autoPaste": autoPaste])
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func refreshMlxStatus() {
        mlxStatus = "Checking…"
        Task { @MainActor in
            let installed = await MLX.isInstalled()
            mlxInstalled = installed
            mlxStatus = installed ? "Installed" : "Not installed"
        }
    }

    func installMlx() {
        mlxBusy = true
        Task { @MainActor in
            do {
                try await MLX.install { message in
                    Task { @MainActor in self.mlxStatus = message }
                }
                mlxInstalled = true
                mlxStatus = "Installed"
            } catch {
                mlxStatus = error.localizedDescription
            }
            mlxBusy = false
        }
    }

    func removeMlx() {
        try? MLX.remove()
        refreshMlxStatus()
    }

    // MARK: - Shortcut recording (click, press a combo; Esc cancels)

    func toggleShortcutRecording() {
        shortcutRecording ? stopShortcutRecording() : startShortcutRecording()
    }

    private func startShortcutRecording() {
        shortcutRecording = true
        shortcutFailed = false
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.stopShortcutRecording()
                return nil
            }
            guard let accelerator = Accelerator.string(
                keyCode: event.keyCode, flags: event.modifierFlags
            ) else { return nil }
            if self.applyShortcut(accelerator) {
                self.shortcut = accelerator
            } else {
                self.shortcutFailed = true
            }
            self.stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        shortcutRecording = false
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("OpenAI") {
                HStack {
                    SecureField(
                        "API Key",
                        text: $model.newKey,
                        prompt: Text(model.hasKey ? "•••••••••••• (saved)" : "sk-…")
                    )
                    Button("Save") { model.saveKey() }
                        .disabled(
                            model.newKey.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
            }

            Section("Transcription") {
                Picker("Engine", selection: $model.engine) {
                    Text("OpenAI Whisper").tag("openai")
                    Text("Local MLX").tag("mlx")
                }
                .pickerStyle(.segmented)
                .onChange(of: model.engine) { model.saveEngine() }

                if model.engine == "mlx" {
                    TextField("Model", text: $model.mlxModel)
                        .onSubmit { model.saveMlxModel() }
                    LabeledContent("Local Engine") {
                        HStack {
                            if model.mlxBusy {
                                ProgressView().controlSize(.small)
                            }
                            Text(model.mlxStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if model.mlxInstalled {
                                Button("Remove") { model.removeMlx() }
                                    .disabled(model.mlxBusy)
                            } else {
                                Button("Install") { model.installMlx() }
                                    .disabled(model.mlxBusy)
                            }
                        }
                    }
                }
            }

            Section("Shortcut") {
                LabeledContent("Toggle Recording") {
                    Button {
                        model.toggleShortcutRecording()
                    } label: {
                        Text(
                            model.shortcutRecording
                                ? "Press keys…"
                                : Accelerator.label(model.shortcut)
                        )
                        .frame(minWidth: 76)
                    }
                    .tint(model.shortcutFailed ? .red : nil)
                    .help(
                        model.shortcutFailed
                            ? "That shortcut is taken by another app." : ""
                    )
                }
            }

            Section("General") {
                Toggle("Paste into the active app", isOn: $model.autoPaste)
                    .onChange(of: model.autoPaste) { model.saveAutoPaste() }
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { model.toggleLaunchAtLogin() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 440)
        .onAppear { model.refreshMlxStatus() }
    }
}
