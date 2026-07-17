import AppKit
import SwiftUI

@main
enum VerseMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            AppDelegate.shared = delegate
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private let panelState = PanelState()
    private let recorder = Recorder()

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var meterTimer: Timer?
    private var toggleHotKeyID: UInt32?
    private var escapeHotKeyID: UInt32?
    private var hideWorkItem: DispatchWorkItem?
    private var activeShortcut = ""

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private lazy var settingsModel = SettingsModel()
    private lazy var historyModel = HistoryModel()

    // VERSE_DEMO=1 shows the recording panel with synthetic levels — used to
    // preview the Liquid Glass UI without touching the microphone.
    private let demoMode = ProcessInfo.processInfo.environment["VERSE_DEMO"] == "1"
    private var demoStart = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeStatusItem()
        makePanel()
        registerToggleShortcut()
        rebuildMenu()

        if demoMode {
            panelState.phase = .recording
            demoStart = Date()
            showPanel()
            startMeterTimer()
        }
    }

    // MARK: - Status item & menu

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()
    }

    private func statusImage() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        switch panelState.phase {
        case .recording:
            let colors = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            return NSImage(
                systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording"
            )?.withSymbolConfiguration(config.applying(colors))
        case .transcribing:
            let image = NSImage(
                systemSymbolName: "ellipsis.circle", accessibilityDescription: "Transcribing"
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            return image
        default:
            let image = NSImage(
                systemSymbolName: "quote.opening", accessibilityDescription: "Verse"
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            return image
        }
    }

    private func updateStatusIcon() {
        statusItem.button?.image = statusImage()
        statusItem.button?.toolTip = switch panelState.phase {
        case .recording: "Verse — recording"
        case .transcribing: "Verse — transcribing"
        default: "Verse"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = switch panelState.phase {
        case .recording: "Stop Recording"
        case .transcribing: "Transcribing…"
        default: "Start Recording"
        }
        let record = NSMenuItem(
            title: title, action: #selector(menuToggleRecording), keyEquivalent: ""
        )
        // Display-only: status item menus are outside the key-equivalent
        // dispatch path, so this renders "F9" without double-firing the
        // Carbon hotkey.
        if let (key, mask) = Accelerator.keyEquivalent(activeShortcut) {
            record.keyEquivalent = key
            record.keyEquivalentModifierMask = mask
        }
        record.target = self
        record.isEnabled = panelState.phase != .transcribing
        menu.addItem(record)
        menu.addItem(.separator())

        let history = NSMenuItem(
            title: "History…", action: #selector(openHistory), keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Verse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))

        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    @objc private func menuToggleRecording() {
        toggleRecording()
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            historyModel.reload()
            historyWindow = makeWindow(
                title: "Verse History",
                size: NSSize(width: 520, height: 640),
                resizable: true,
                view: HistoryView(model: historyModel)
            )
            historyWindow?.minSize = NSSize(width: 380, height: 400)
        }
        presentWindow(historyWindow)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsModel.applyShortcut = { [weak self] accelerator in
                self?.applyShortcut(accelerator) ?? false
            }
            settingsWindow = makeWindow(
                title: "Verse Settings",
                size: NSSize(width: 460, height: 680),
                resizable: false,
                view: SettingsView(model: settingsModel)
            )
        }
        presentWindow(settingsWindow)
    }

    private func makeWindow(
        title: String, size: NSSize, resizable: Bool, view: some View
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        let hosting = NSHostingView(rootView: AnyView(view.ignoresSafeArea()))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])
        window.contentView = effect
        window.center()
        return window
    }

    private func presentWindow(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Panel

    private func makePanel() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: RecordingPanelView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let view = RecordingPanelView(
            state: panelState,
            onStop: { [weak self] in self?.stopRecording() },
            onCancel: { [weak self] in self?.cancelRecording() }
        )
        panel.contentView = NSHostingView(rootView: view)
    }

    private func showPanel() {
        hideWorkItem?.cancel()
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func hidePanel(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            panelState.phase = .idle
            panelState.resetMeter()
            updateStatusIcon()
            rebuildMenu()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func positionPanel() {
        let size = RecordingPanelView.size
        var origin: NSPoint

        if let button = statusItem.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.minY - 8 - size.height
            )
        } else {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            origin = NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 16)
        }

        if let screen = NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = max(origin.y, screen.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Recording state machine

    private func toggleRecording() {
        switch panelState.phase {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            stopRecording()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        Task { @MainActor in
            guard await Recorder.requestMicAccess() else {
                showError("Allow microphone access in System Settings → Privacy & Security.")
                return
            }
            do {
                try recorder.start()
            } catch {
                showError(error.localizedDescription)
                return
            }
            panelState.resetMeter()
            panelState.phase = .recording
            showPanel()
            startMeterTimer()
            registerEscapeHotKey()
            updateStatusIcon()
            rebuildMenu()
        }
    }

    private func stopRecording() {
        guard panelState.phase == .recording else { return }
        stopMeterTimer()
        unregisterEscapeHotKey()
        guard let (url, durationMs) = recorder.stop() else {
            hidePanel(after: 0)
            return
        }
        panelState.phase = .transcribing
        updateStatusIcon()
        rebuildMenu()
        Task { @MainActor in
            await transcribe(url: url, durationMs: durationMs)
        }
    }

    private func cancelRecording() {
        guard panelState.phase == .recording else { return }
        stopMeterTimer()
        unregisterEscapeHotKey()
        recorder.cancel()
        panel.orderOut(nil)
        panelState.phase = .idle
        panelState.resetMeter()
        updateStatusIcon()
        rebuildMenu()
    }

    private func transcribe(url: URL, durationMs: Int) async {
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = AppSettings.load()
        do {
            let raw: String = settings.engine == "mlx"
                ? try await MLX.transcribe(fileURL: url, model: settings.mlxModel)
                : try await Transcriber.transcribe(fileURL: url, apiKey: settings.apiKey)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw TranscriberError.badResponse("The transcript came back empty.")
            }

            Paste.copyToClipboard(text)
            History.append(text: text, engine: settings.engine, durationMs: durationMs)

            var pasted = false
            if settings.autoPaste {
                if !Paste.isTrusted { Paste.promptForAccessibility() }
                pasted = Paste.pasteIntoFrontApp()
            }

            panelState.doneMessage = pasted ? "Pasted" : "Copied to clipboard"
            panelState.doneDetail = !pasted && settings.autoPaste
                ? "Allow Verse under Privacy & Security → Accessibility to auto-paste."
                : preview(text)
            panelState.phase = .done
            updateStatusIcon()
            rebuildMenu()
            hidePanel(after: 1.4)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        panelState.errorMessage = message
        panelState.phase = .error
        showPanel()
        updateStatusIcon()
        rebuildMenu()
        hidePanel(after: 3.0)
    }

    private func preview(_ text: String) -> String {
        let compact = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        return compact.count > 64 ? String(compact.prefix(64)) + "…" : compact
    }

    // MARK: - Meter

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) {
            [weak self] _ in
            // The timer is scheduled on the main run loop.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.demoMode {
                    let t = Date().timeIntervalSince(self.demoStart)
                    let level = 0.18 + 0.5 * abs(sin(t * 2.6)) + Double.random(in: 0...0.18)
                    self.panelState.push(level: min(1, level))
                    self.panelState.elapsed = t
                } else {
                    self.panelState.push(level: self.recorder.level())
                    self.panelState.elapsed = self.recorder.elapsed()
                }
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: - Hotkeys

    private func registerToggleShortcut() {
        let settings = AppSettings.load()
        for candidate in [settings.shortcut, "Alt+Space", "Control+Alt+Space"] {
            guard let (keyCode, modifiers) = Accelerator.parse(candidate) else { continue }
            let registered = HotKeyCenter.shared.register(
                keyCode: keyCode, modifiers: modifiers
            ) { [weak self] in
                self?.toggleRecording()
            }
            if let registered {
                toggleHotKeyID = registered
                activeShortcut = candidate
                panelState.shortcutLabel = Accelerator.label(candidate)
                return
            }
        }
    }

    /// Swaps the global hotkey from Settings; restores the old one on failure.
    func applyShortcut(_ accelerator: String) -> Bool {
        guard let (keyCode, modifiers) = Accelerator.parse(accelerator) else { return false }
        if let id = toggleHotKeyID { HotKeyCenter.shared.unregister(id) }
        toggleHotKeyID = nil

        let registered = HotKeyCenter.shared.register(
            keyCode: keyCode, modifiers: modifiers
        ) { [weak self] in
            self?.toggleRecording()
        }
        if let registered {
            toggleHotKeyID = registered
            activeShortcut = accelerator
            panelState.shortcutLabel = Accelerator.label(accelerator)
            AppSettings.save(["shortcut": accelerator])
            rebuildMenu()
            return true
        }
        registerToggleShortcut()
        rebuildMenu()
        return false
    }

    private func registerEscapeHotKey() {
        guard escapeHotKeyID == nil,
              let (keyCode, modifiers) = Accelerator.parse("Escape") else { return }
        escapeHotKeyID = HotKeyCenter.shared.register(keyCode: keyCode, modifiers: modifiers) {
            [weak self] in
            self?.cancelRecording()
        }
    }

    private func unregisterEscapeHotKey() {
        if let id = escapeHotKeyID { HotKeyCenter.shared.unregister(id) }
        escapeHotKeyID = nil
    }
}
