import AppKit
import SwiftUI

/// Colors and small building blocks. Black background, one accent, nothing else shouting.
enum Theme {
    static let background = Color(hex: 0x050506)
    static let surface = Color(hex: 0x0E0E10)
    static let surfaceRaised = Color(hex: 0x17171A)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color(hex: 0xF3F3F4)
    static let secondary = Color(hex: 0x8C8C94)
    static let accent = Color(hex: 0x7AA2FF)
    static let accentSoft = Color(hex: 0x7AA2FF).opacity(0.14)
    static let good = Color(hex: 0x4ADE80)
    static let warning = Color(hex: 0xF5A524)
    static let warningSoft = Color(hex: 0xF5A524).opacity(0.14)
    static let danger = Color(hex: 0xFF6369)
    static let dangerSoft = Color(hex: 0xFF6369).opacity(0.14)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondary)
    }
}

/// A rounded square with an SF Symbol inside.
struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Inline notice. Use `.warning` for things that need a decision, `.info` for explanations.
struct Notice: View {
    enum Style { case info, warning, danger }

    let style: Style
    let text: String

    private var tint: Color {
        switch style {
        case .info: return Theme.accent
        case .warning: return Theme.warning
        case .danger: return Theme.danger
        }
    }

    private var symbol: String {
        switch style {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .danger: return "exclamationmark.octagon"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color.black
        case .secondary: return Theme.text
        case .destructive: return Theme.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .secondary: return Theme.surfaceRaised
        case .destructive: return Theme.dangerSoft
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillDestructive: PillButtonStyle { PillButtonStyle(kind: .destructive) }
}

/// Small text-only button for rows.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(Theme.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Window helpers

/// Reports the NSWindow that hosts a SwiftUI view.
struct WindowObserver: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        ObserverView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ObserverView: NSView {
        let onResolve: (NSWindow) -> Void

        init(onResolve: @escaping (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                self?.onResolve(window)
            }
        }
    }
}
