import AppKit
import SwiftUI
import TapCore

private struct DictationPillView: View {
    @ObservedObject var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if !reduceMotion {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .strokeBorder(Theme.good, lineWidth: 2)
                            .frame(width: 34, height: 34)
                            .scaleEffect(pulse ? 1.9 : 0.7)
                            .opacity(pulse ? 0 : 0.7)
                            .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false).delay(Double(index) * 0.4), value: pulse)
                    }
                }
                Circle().fill(Theme.good.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "mic.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.good)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Listening").font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                    meter
                }
                if !controller.typingNote.isEmpty {
                    Text(controller.typingNote)
                        .font(.caption2)
                        .foregroundStyle(controller.typingNote.hasPrefix("Typing") ? Theme.good : Theme.warning)
                        .lineLimit(2)
                }
                Text(controller.transcript.isEmpty ? "Speak now. Double tap again to finish." : DictationText.tail(controller.transcript))
                    .font(.caption)
                    .foregroundStyle(controller.transcript.isEmpty ? Theme.secondary : Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Theme.surfaceRaised.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .padding(12)
        .onAppear { pulse = true }
    }

    private var meter: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                let threshold = Double(index + 1) / 7.0
                Capsule()
                    .fill(controller.level >= threshold * 0.85 ? Theme.good : Theme.surfaceRaised)
                    .frame(width: 4, height: 6 + CGFloat(index) * 2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: controller.level)
    }
}

/// A small floating pill that stays up while dictation is listening and never takes focus,
/// so the text still goes to the app you were typing in.
@MainActor
final class DictationPill {
    private var panel: NSPanel?

    func show(controller: DictationController) {
        let panel = self.panel ?? makePanel(controller: controller)
        self.panel = panel
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func makePanel(controller: DictationController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 404, height: 100),
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
        panel.contentView = NSHostingView(rootView: DictationPillView(controller: controller))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 110))
    }
}
