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

    func push(level: Double) {
        samples.removeFirst()
        samples.append(level)
    }

    func resetMeter() {
        samples = Array(repeating: 0, count: Self.meterBarCount)
        elapsed = 0
    }
}

struct RecordingPanelView: View {
    static let size = CGSize(width: 300, height: 148)

    @ObservedObject var state: PanelState
    var onStop: () -> Void
    var onCancel: () -> Void

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
        .frame(width: Self.size.width, height: Self.size.height)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 26))
    }

    private var recording: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text(timeText)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Spacer()
                if !state.shortcutLabel.isEmpty {
                    Text(state.shortcutLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            meter

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.glass)
                Button("Stop", action: onStop)
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
