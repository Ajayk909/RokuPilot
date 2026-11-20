import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.067)
    static let surface = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let secondaryText = Color.white.opacity(0.55)
    static let violet = Color(red: 0.49, green: 0.36, blue: 1.0)
    static let cyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let green = Color(red: 0.2, green: 0.83, blue: 0.6)

    static let accent = LinearGradient(colors: [violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Subtle animated backdrop used behind every screen.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.violet.opacity(0.28))
                .frame(width: 420)
                .blur(radius: 120)
                .offset(x: -140, y: -320)
            Circle()
                .fill(Theme.cyan.opacity(0.16))
                .frame(width: 380)
                .blur(radius: 120)
                .offset(x: 160, y: 360)
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// Springy press effect for every tappable control.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    func screenBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Backdrop())
    }
}
