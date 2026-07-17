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
    @Published var notifications: Bool
    @Published var livePreview: Bool
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

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    init() {
        let settings = AppSettings.load()
        hasKey = !settings.apiKey.isEmpty
        engine = settings.engine
        mlxModel = settings.mlxModel
        autoPaste = settings.autoPaste
        notifications = settings.notifications
        livePreview = settings.livePreview
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

    func saveNotifications() {
        AppSettings.save(["notifications": notifications])
    }

    func saveLivePreview() {
        AppSettings.save(["livePreview": livePreview])
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
            mlxStatus = if installed {
                MLX.isSharedWithV1
                    ? "Using Verse 1's installed engine (read-only)."
                    : "Installed at \(MLX.root.path)."
            } else {
                "Downloads a private Python environment with mlx-whisper (~1 GB with a model)."
            }
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
                mlxStatus = "Installed at \(MLX.root.path)."
            } catch {
                mlxStatus = error.localizedDescription
            }
            mlxBusy = false
        }
    }

    func removeMlx() {
        guard !MLX.isSharedWithV1 else {
            mlxStatus = "This engine belongs to Verse 1 — manage it there."
            return
        }
        try? MLX.remove()
        refreshMlxStatus()
    }

    func openMlxFolder() {
        try? FileManager.default.createDirectory(
            at: MLX.root, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(MLX.root)
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
        VStack(spacing: 0) {
            WindowHeader(title: "Verse Dev")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    recordingGroup
                    outputGroup
                    transcriptionGroup
                    signature
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .onAppear { model.refreshMlxStatus() }
    }

    private var recordingGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Recording")
            HStack(spacing: 10) {
                Text("Start / stop recording")
                    .font(.system(size: 13))
                Spacer()
                Button {
                    model.toggleShortcutRecording()
                } label: {
                    Text(
                        model.shortcutRecording
                            ? "Press keys…"
                            : Accelerator.label(model.shortcut)
                    )
                    .monospacedDigit()
                    .frame(minWidth: 82)
                }
                .buttonStyle(VerseButtonStyle(accent: model.shortcutRecording))
                .tint(model.shortcutFailed ? .red : .accentColor)
            }
            .padding(.vertical, 6)
            Hint(text: model.shortcutFailed
                ? "That shortcut is taken by another app — try a different one."
                : "Click, then press the keys you want — a function key alone (like F5) or any combo with ⌘⌥⌃⇧. Esc cancels. Press once to record, again to transcribe.")
            HStack(spacing: 10) {
                Text("Live transcript preview while recording")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $model.livePreview)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .onChange(of: model.livePreview) { model.saveLivePreview() }
            }
            .padding(.vertical, 6)
            Hint(text: "Experimental — shows Apple's on-device transcription in the panel as you speak. Apple Speech engine only.")
        }
    }

    private var outputGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Output")
            HStack(spacing: 10) {
                Text("Paste into the active app when done")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $model.autoPaste)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .onChange(of: model.autoPaste) { model.saveAutoPaste() }
            }
            .padding(.vertical, 6)
            Hint(text: "The transcript is always copied to the clipboard. With this on, it is also typed into whatever text box has focus (needs Accessibility permission the first time).")
            HStack(spacing: 10) {
                Text("Notify when the transcript is ready")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $model.notifications)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .onChange(of: model.notifications) { model.saveNotifications() }
            }
            .padding(.vertical, 6)
            HStack(spacing: 10) {
                Text("Launch at login")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $model.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .onChange(of: model.launchAtLogin) { model.toggleLaunchAtLogin() }
            }
            .padding(.vertical, 6)
        }
    }

    private var transcriptionGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Transcription")
            HStack(spacing: 10) {
                Text("Engine")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $model.engine) {
                    Text("Apple Speech").tag("apple")
                    Text("OpenAI API").tag("openai")
                    Text("Local MLX").tag("mlx")
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: model.engine) { model.saveEngine() }
            }
            .padding(.vertical, 6)

            switch model.engine {
            case "apple":
                Hint(text: "Apple's on-device speech models — private, free, no setup. Uses your system language.")
            case "mlx":
                HStack(spacing: 10) {
                    Text("MLX model")
                        .font(.system(size: 13))
                    TextField("", text: $model.mlxModel)
                        .fieldChrome()
                        .onSubmit { model.saveMlxModel() }
                }
                .padding(.vertical, 6)
                HStack(spacing: 6) {
                    if model.mlxBusy {
                        ProgressView().controlSize(.small)
                    }
                    Hint(text: model.mlxStatus)
                    Spacer()
                    if model.mlxInstalled {
                        Button("Remove") { model.removeMlx() }
                            .buttonStyle(VerseButtonStyle())
                            .disabled(model.mlxBusy)
                    } else {
                        Button("Install") { model.installMlx() }
                            .buttonStyle(VerseButtonStyle())
                            .disabled(model.mlxBusy)
                    }
                    Button("Open Folder") { model.openMlxFolder() }
                        .buttonStyle(VerseButtonStyle())
                }
                .padding(.vertical, 6)
            default:
                HStack(spacing: 10) {
                    SecureField("sk-…", text: $model.newKey)
                        .fieldChrome()
                        .onSubmit { model.saveKey() }
                    Button("Save") { model.saveKey() }
                        .buttonStyle(VerseButtonStyle())
                        .disabled(model.newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 6)
                Hint(text: model.hasKey
                    ? "A key is saved. Enter a new one to replace it."
                    : "No key saved yet.")
            }
        }
    }

    private var signature: some View {
        VStack(spacing: 0) {
            Text("”")
                .font(.custom("Didot", size: 22).weight(.bold))
                .foregroundStyle(.secondary)
            Text("Verse \(model.version)")
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.4)
                .padding(.top, 6)
            Text("by LMC4S  ·  AGPL-3.0")
                .font(.system(size: 10.5))
                .kerning(0.3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }
}
