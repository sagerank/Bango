import AppKit
import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    @Published var feedback = Feedback(symbol: "hand.tap", title: "", detail: "")
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: model.feedback.symbol,
                tint: model.feedback.isError ? Theme.danger : Theme.accent,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(model.feedback.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(model.feedback.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background(Theme.surfaceRaised.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .padding(12)
    }
}

/// A small confirmation that floats near the bottom of the screen and never takes focus.
@MainActor
final class HUDController {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideItem: DispatchWorkItem?

    func show(_ feedback: Feedback) {
        model.feedback = feedback
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        hideItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.hide() }
        }
        hideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (feedback.isError ? 3.0 : 1.6), execute: item)
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
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 84),
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
