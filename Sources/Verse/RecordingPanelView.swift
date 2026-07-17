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

    func resetMeter() {
        samples = Array(repeating: 0, count: Self.meterBarCount)
        elapsed = 0
        previewFinal = ""
        previewVolatile = ""
    }
}

/// Faithful port of v1's panel: dark HUD, white-opacity typography, ghost and
/// red-primary buttons, spectrum meter — rendered on maximally clear glass.
struct RecordingPanelView: View {
    static let size = CGSize(width: 300, height: 148)
    static let previewSize = CGSize(width: 300, height: 196)

    static let red = Color(red: 1.0, green: 69 / 255, blue: 58 / 255)

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
                status(spinner: true, line: "Transcribing…")
            case .done:
                status(check: true, line: state.doneMessage, detail: state.doneDetail)
            case .error:
                status(cross: true, line: state.errorMessage)
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 26))
        // Liquid-glass rim light: the .clear variant is flat by design (the
        // specular edge belongs to .regular), so draw the lensing signature —
        // bright top rim, dim sides, faint bottom reflection — ourselves.
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0),
                            .init(color: .white.opacity(0.14), location: 0.25),
                            .init(color: .white.opacity(0.05), location: 0.6),
                            .init(color: .white.opacity(0.22), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .colorScheme(.dark)
    }

    // MARK: - Recording view

    private var recording: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulsingDot()
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.13)
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text(timeText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
            }

            meter

            if state.showPreview {
                (Text(state.previewFinal)
                    .foregroundColor(.white.opacity(0.85))
                    + Text(state.previewVolatile)
                    .foregroundColor(.white.opacity(0.55))
                    .underline(pattern: .dot, color: .white.opacity(0.4)))
                    .font(.system(size: 12))
                    .lineSpacing(2.5)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, maxHeight: 44, alignment: .bottomLeading)
            }

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button(action: onStop) {
                    HStack(spacing: 7) {
                        Text("Done")
                        if !state.shortcutLabel.isEmpty {
                            Text(state.shortcutLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.black.opacity(0.25))
                                )
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var meter: some View {
        let height: CGFloat = state.showPreview ? 22 : 36
        return HStack(alignment: .center, spacing: 4) {
            ForEach(Array(state.samples.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.35 + level * 0.55))
                    .frame(height: max(4, level * height))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height)
        .animation(.linear(duration: 1.0 / 30), value: state.samples)
    }

    // MARK: - Status views (transcribing / done / error)

    private func status(
        spinner: Bool = false,
        check: Bool = false,
        cross: Bool = false,
        line: String,
        detail: String = ""
    ) -> some View {
        VStack(spacing: 12) {
            if spinner {
                Spinner()
            }
            if check {
                Text("✓")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if cross {
                Text("!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Self.red)
            }
            Text(line)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
    }

    private var timeText: String {
        let total = Int(state.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// v1's .record-dot: 10px #ff453a, soft glow, 1.4s ease-in-out pulse.
private struct PulsingDot: View {
    private let dimmed = State(initialValue: false)

    var body: some View {
        Circle()
            .fill(RecordingPanelView.red)
            .frame(width: 10, height: 10)
            .shadow(color: RecordingPanelView.red.opacity(0.8), radius: 4)
            .opacity(dimmed.wrappedValue ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed.wrappedValue = true
                }
            }
    }
}

/// v1's .spinner: 22px ring, white top arc, 0.8s linear spin.
private struct Spinner: View {
    private let spinning = State(initialValue: false)

    var body: some View {
        Circle()
            .stroke(.white.opacity(0.2), lineWidth: 2.5)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(
                        lineWidth: 2.5, lineCap: .round
                    ))
                    .rotationEffect(.degrees(spinning.wrappedValue ? 360 : 0))
            )
            .frame(width: 22, height: 22)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinning.wrappedValue = true
                }
            }
    }
}

/// v1's button.ghost: white 10% fill, radius 8, 12px semibold, press scale.
private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// v1's button.primary: #ff453a at 85% (100% pressed), radius 8.
private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(RecordingPanelView.red.opacity(
                        configuration.isPressed ? 1 : 0.85
                    ))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
