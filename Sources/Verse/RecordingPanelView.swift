import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    enum Phase {
        case idle, recording, transcribing, done, error
    }

    static let meterBarCount = 28

    @Published var phase: Phase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var samples: [Double] = Array(repeating: 0, count: meterBarCount)
    @Published var doneMessage = "Copied to clipboard"
    @Published var doneDetail = ""
    @Published var errorMessage = "Something went wrong."
    @Published var shortcutLabel = ""
    @Published var showPreview = false
    @Published var previewFinal = ""
    @Published var previewVolatile = ""

    func push(level: Double) {
        samples.removeFirst()
        samples.append(level)
    }

    func resetMeter() {
        samples = Array(repeating: 0, count: Self.meterBarCount)
        elapsed = 0
        previewFinal = ""
        previewVolatile = ""
    }
}

struct RecordingPanelView: View {
    static let size = CGSize(width: 300, height: 148)
    static let previewSize = CGSize(width: 300, height: 196)

    @ObservedObject var state: PanelState
    var onStop: () -> Void
    var onCancel: () -> Void

    private var currentSize: CGSize {
        state.showPreview ? Self.previewSize : Self.size
    }

    var body: some View {
        ZStack {
            switch state.phase {
            case .idle, .recording:
                recording
            case .transcribing:
                status {
                    ProgressView().controlSize(.small)
                } title: {
                    Text("Transcribing…")
                }
            case .done:
                status {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                } title: {
                    Text(state.doneMessage)
                } detail: {
                    Text(state.doneDetail)
                }
            case .error:
                status {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                } title: {
                    Text("Transcription failed")
                } detail: {
                    Text(state.errorMessage)
                }
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 26))
    }

    private var recording: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(timeText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            meter

            if state.showPreview {
                (Text(state.previewFinal)
                    + Text(state.previewVolatile).foregroundStyle(.secondary))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, maxHeight: 44, alignment: .bottomLeading)
            }

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.glass)
                Button(action: onStop) {
                    HStack(spacing: 5) {
                        Text("Done")
                        if !state.shortcutLabel.isEmpty {
                            Text(state.shortcutLabel)
                                .font(.system(size: 10.5, weight: .semibold))
                                .opacity(0.7)
                        }
                    }
                }
                .buttonStyle(.glassProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(state.samples.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.primary.opacity(0.35 + level * 0.55))
                    .frame(height: max(4, level * 44))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 44)
        .animation(.linear(duration: 1.0 / 30), value: state.samples)
    }

    private func status(
        @ViewBuilder icon: () -> some View,
        @ViewBuilder title: () -> some View,
        @ViewBuilder detail: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 8) {
            icon()
            title()
                .font(.headline)
            detail()
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(16)
    }

    private var timeText: String {
        let total = Int(state.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
