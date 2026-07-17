import SwiftUI

/// Verse 1.x design language, translated from the Electron CSS: flat
/// translucent controls with hairline borders over window vibrancy,
/// centered 48pt titlebar, uppercase dim section headers.
enum Theme {
    static let fieldBackground = Color.primary.opacity(0.06)
    static let fieldBorder = Color.primary.opacity(0.13)
    static let rowHover = Color.primary.opacity(0.06)
    static let cornerRadius: CGFloat = 7
}

struct VerseButtonStyle: ButtonStyle {
    var accent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.13 : 0.07),
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.fieldBorder))
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Theme.fieldBackground,
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.fieldBorder)
            )
    }
}

extension View {
    func fieldChrome() -> some View {
        modifier(FieldChrome())
    }
}

/// The 48pt centered titlebar from v1; the window's real titlebar is
/// transparent and the traffic lights float over this.
struct WindowHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.66)
            .foregroundStyle(.secondary)
    }
}

struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hover tracking without the @State macro (unavailable outside Xcode):
/// a manually declared SwiftUI.State — exactly what the macro expands to —
/// discovered by SwiftUI through reflection.
struct Hoverable<Content: View>: View {
    private let hovering = State(initialValue: false)
    @ViewBuilder private let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(hovering.wrappedValue)
            .onHover { hovering.wrappedValue = $0 }
    }
}
