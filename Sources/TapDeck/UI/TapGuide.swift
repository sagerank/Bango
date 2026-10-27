import SwiftUI
import TapCore

/// A simple drawing of a MacBook that pulses on the exact spot to tap.
struct LaptopGuide: View {
    enum Mood { case waiting, heard, success }

    var spot: TapLesson.Spot
    var taps = 1
    var mood: Mood = .waiting

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 280, height: 170)

    private var tint: Color { mood == .success ? Theme.good : Theme.accent }

    /// Where the spot is, as a fraction of the picture.
    private var point: CGPoint {
        switch spot {
        case .anywhere: return CGPoint(x: 0.74, y: 0.82)
        case .left: return CGPoint(x: 0.22, y: 0.82)
        case .right: return CGPoint(x: 0.78, y: 0.82)
        case .top: return CGPoint(x: 0.5, y: 0.555)
        }
    }

    var body: some View {
        ZStack {
            // Screen.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .frame(width: size.width * 0.6, height: size.height * 0.5)
                .position(x: size.width / 2, y: size.height * 0.27)
            // Base.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .frame(width: size.width * 0.9, height: size.height * 0.4)
                .position(x: size.width / 2, y: size.height * 0.77)
            // Keyboard and trackpad.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: size.width * 0.62, height: size.height * 0.13)
                .position(x: size.width / 2, y: size.height * 0.64)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
                .frame(width: size.width * 0.2, height: size.height * 0.1)
                .position(x: size.width / 2, y: size.height * 0.84)

            spotView
                .position(x: size.width * point.x, y: size.height * point.y)
        }
        .frame(width: size.width, height: size.height)
        .onAppear { pulse = true }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: mood)
    }

    private var spotView: some View {
        ZStack {
            Circle().fill(tint.opacity(0.22)).frame(width: 30, height: 30)
            if !reduceMotion && mood != .success {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(pulse ? 2.1 : 0.7)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            Image(systemName: mood == .success ? "checkmark.circle.fill" : "hand.tap.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(mood == .heard ? 1.35 : 1)
        }
    }
}

/// Shows how many taps to make: one dot per tap.
struct TapBeats: View {
    let count: Int
    var done = false
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(done || index < lit ? (done ? Theme.good : Theme.accent) : Theme.surfaceRaised)
                    .frame(width: 14, height: 14)
                    .scaleEffect(!done && index == lit - 1 ? 1.3 : 1)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: lit)
        .task(id: count) {
            // A looping preview of the rhythm: tap, tap, tap, pause.
            while !Task.isCancelled && !done {
                lit = 0
                try? await Task.sleep(nanoseconds: 700_000_000)
                for step in 1...count {
                    lit = step
                    try? await Task.sleep(nanoseconds: 220_000_000)
                }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
    }
}
