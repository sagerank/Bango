import AppKit
import ImageIO
import SwiftUI
import TapCore

@MainActor
final class HUDModel: ObservableObject {
    @Published var feedback = Feedback(symbol: "hand.tap", title: "", detail: "")
}

// MARK: - Animated visuals

/// Finds an installed app's icon by the name the person typed.
enum AppIcons {
    static func icon(named name: String) -> NSImage? {
        let base = name.hasSuffix(".app") ? name : name + ".app"
        let folders = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities",
            "/Applications/Utilities", NSHomeDirectory() + "/Applications",
        ]
        for folder in folders {
            let path = folder + "/" + base
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }
}

/// A small preview of a saved screenshot, cheap enough to make while the HUD is appearing.
enum Thumbnail {
    static func load(path: String, maxSize: Int = 160) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let url = URL(fileURLWithPath: path) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }
}

private struct PopIcon: View {
    let symbol: String
    let tint: Color
    @State private var shown = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.16))
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: shown)
        }
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shown = true } }
    }
}

/// Camera shutter: a ripple, a viewfinder that snaps in, and the picture itself when there is one.
private struct ShutterVisual: View {
    let path: String?
    let toClipboard: Bool
    @State private var snapped = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent.opacity(0.16))
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
                .scaleEffect(snapped ? 1.7 : 0.5)
                .opacity(snapped ? 0 : 0.9)
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            } else {
                Image(systemName: toClipboard ? "doc.on.clipboard.fill" : "camera.aperture")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(snapped ? 90 : 0))
                    .scaleEffect(snapped ? 1 : 1.5)
            }
            Image(systemName: "viewfinder")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Theme.accent.opacity(0.8))
                .scaleEffect(snapped ? 1 : 1.5)
                .opacity(snapped ? 0.9 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { snapped = true } }
        .task {
            guard let path else { return }
            let image = await Thumbnail.load(path: path)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { thumbnail = image }
        }
    }
}

/// Microphone: green rings pulse out when it is live, a red slash drops in when it is muted.
private struct MicrophoneVisual: View {
    let muted: Bool
    @State private var pop = false
    @State private var pulse = false

    private var tint: Color { muted ? Theme.danger : Theme.good }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.16))
            if !muted {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .scaleEffect(pulse ? 1.9 : 0.6)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false).delay(Double(index) * 0.35), value: pulse)
                }
            }
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(pop ? 1 : 0.4)
                .rotationEffect(.degrees(pop || !muted ? 0 : -16))
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { pop = true }
            pulse = true
        }
    }
}

/// An app launch: its own icon springs up with a soft glow.
private struct AppVisual: View {
    let name: String
    @State private var up = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.35))
                .blur(radius: 14)
                .scaleEffect(up ? 1.1 : 0.3)
                .opacity(up ? 0.7 : 0)
            if let icon = AppIcons.icon(named: name) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
            }
        }
        .scaleEffect(up ? 1 : 0.4)
        .offset(y: up ? 0 : 10)
        .opacity(up ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) { up = true } }
    }
}

private struct HUDVisual: View {
    let feedback: Feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if feedback.isError || reduceMotion {
            IconBadge(symbol: feedback.symbol, tint: feedback.isError ? Theme.danger : Theme.accent, size: 44)
        } else {
            switch feedback.kind {
            case .generic:
                PopIcon(symbol: feedback.symbol, tint: Theme.accent)
            case .screenshot(let toClipboard):
                ShutterVisual(path: feedback.capturePath, toClipboard: toClipboard)
            case .microphone(let muted):
                MicrophoneVisual(muted: muted)
            case .app(let name):
                AppVisual(name: name)
            }
        }
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        let feedback = model.feedback
        HStack(spacing: 14) {
            HUDVisual(feedback: feedback)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(feedback.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .id(feedback.id)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 340, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Theme.surfaceRaised.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .padding(12)
    }
}

// MARK: - Screen flash

/// A quick white flash over the screen, like a camera shutter. Shown after the picture is taken,
/// so it never ends up in the screenshot. Skipped when Reduce Motion is on.
@MainActor
enum ScreenFlash {
    static func fire() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let screen = NSScreen.main else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .white
        panel.alphaValue = 0
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.05
            panel.animator().alphaValue = 0.4
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in panel.orderOut(nil) }
            })
        })
    }
}

// MARK: - Window

/// A small confirmation that floats near the bottom of the screen and never takes focus.
@MainActor
final class HUDController {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideItem: DispatchWorkItem?

    func show(_ feedback: Feedback) {
        if case .screenshot = feedback.kind, !feedback.isError { ScreenFlash.fire() }

        model.feedback = feedback
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        hideItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.hide() }
        }
        hideItem = item
        let visible: Double = feedback.isError ? 3.0 : (feedback.capturePath != nil ? 2.4 : 1.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + visible, execute: item)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 364, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 72)
        panel.setFrameOrigin(origin)
    }
}
