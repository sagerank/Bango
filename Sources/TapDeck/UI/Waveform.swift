import SwiftUI

/// Live signal strength with the tap threshold drawn as a dashed line.
struct WaveformView: View {
    let values: [Double]
    let threshold: Double
    /// Values at or above this height are clipped. Matches the monitor's 0...1.2 range.
    private let ceiling = 1.2

    var body: some View {
        Canvas { context, size in
            // Zoom so that small taps are visible: the threshold sits near the middle of the view.
            let scale = threshold > 0 ? min(max(0.5 / threshold, 1), 40) : 1

            func y(for value: Double) -> CGFloat {
                let scaled = min(max(value * scale, 0), 1)
                return size.height - CGFloat(scaled) * size.height
            }

            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(base, with: .color(.white.opacity(0.08)), lineWidth: 1)

            var line = Path()
            let thresholdY = y(for: threshold)
            line.move(to: CGPoint(x: 0, y: thresholdY))
            line.addLine(to: CGPoint(x: size.width, y: thresholdY))
            context.stroke(line, with: .color(Theme.warning.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(values.count - 1, 1))
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: CGFloat(index) * step, y: y(for: min(value, ceiling)))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
