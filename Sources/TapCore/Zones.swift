import Foundation

public enum ZoneError: Error, Equatable {
    case notEnoughSamples(TapZone)
    case noSignal(TapZone)
    case inconsistent(TapZone)
    case indistinguishable(TapZone, TapZone)

    public var message: String {
        switch self {
        case .notEnoughSamples(let z): return "Tap the \(z.title.lowercased()) side at least 3 times."
        case .noSignal(let z): return "No usable motion was recorded for the \(z.title.lowercased()) side."
        case .inconsistent(let z): return "The \(z.title.lowercased()) taps were too different from each other. Tap the same spot each time."
        case .indistinguishable(let a, let b): return "\(a.title) and \(b.title) feel the same to the sensor on this Mac. Try tapping farther apart."
        }
    }
}

/// Learned model that tells left, right and top taps apart.
///
/// The sensor axes and rotation signs differ between Mac models and display angles, so nothing
/// is hard coded. The user taps each zone a few times, the model stores the average direction
/// signature of each zone, and later taps are matched by cosine similarity.
/// Experimental: reliability varies by model and must be checked on real hardware.
public struct ZoneModel: Codable, Equatable, Sendable {
    public var left: [Double]
    public var right: [Double]
    public var top: [Double]
    /// Best match must be at least this similar to a zone to count.
    public var minSimilarity: Double
    /// Best match must beat the runner up by this much.
    public var minMargin: Double

    public init(
        left: [Double],
        right: [Double],
        top: [Double],
        minSimilarity: Double = 0.6,
        minMargin: Double = 0.12
    ) {
        self.left = left
        self.right = right
        self.top = top
        self.minSimilarity = minSimilarity
        self.minMargin = minMargin
    }

    public func classify(_ features: ImpactFeatures) -> TapZone {
        let v = features.directionVector
        guard v.contains(where: { $0 != 0 }) else { return .any }
        let scored: [(TapZone, Double)] = [
            (.left, Self.cosine(v, left)),
            (.right, Self.cosine(v, right)),
            (.top, Self.cosine(v, top)),
        ]
        let ranked = scored.sorted { $0.1 > $1.1 }
        guard ranked[0].1 >= minSimilarity, ranked[0].1 - ranked[1].1 >= minMargin else {
            return .any
        }
        return ranked[0].0
    }

    public static func learn(
        left: [ImpactFeatures],
        right: [ImpactFeatures],
        top: [ImpactFeatures]
    ) throws -> ZoneModel {
        let l = try centroid(left, zone: .left)
        let r = try centroid(right, zone: .right)
        let t = try centroid(top, zone: .top)

        let pairs: [(TapZone, [Double], TapZone, [Double])] = [
            (.left, l, .right, r),
            (.left, l, .top, t),
            (.right, r, .top, t),
        ]
        for (za, a, zb, b) in pairs where cosine(a, b) > 0.85 {
            throw ZoneError.indistinguishable(za, zb)
        }
        return ZoneModel(left: l, right: r, top: t)
    }

    private static func centroid(_ samples: [ImpactFeatures], zone: TapZone) throws -> [Double] {
        guard samples.count >= 3 else { throw ZoneError.notEnoughSamples(zone) }
        let vectors = samples.map { $0.directionVector }.filter { $0.contains(where: { $0 != 0 }) }
        guard vectors.count >= 3 else { throw ZoneError.noSignal(zone) }

        var sum = [Double](repeating: 0, count: 6)
        for v in vectors {
            for i in 0..<6 { sum[i] += v[i] }
        }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { throw ZoneError.noSignal(zone) }
        let center = sum.map { $0 / norm }

        let meanSimilarity = vectors.reduce(0) { $0 + cosine($1, center) } / Double(vectors.count)
        guard meanSimilarity >= 0.7 else { throw ZoneError.inconsistent(zone) }
        return center
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denominator = (na * nb).squareRoot()
        return denominator > 0 ? dot / denominator : 0
    }
}
