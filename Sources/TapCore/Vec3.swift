import Foundation

/// Minimal 3-vector so the core has no dependency on simd (which is Apple only).
public struct Vec3: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    public static func + (l: Vec3, r: Vec3) -> Vec3 {
        Vec3(l.x + r.x, l.y + r.y, l.z + r.z)
    }

    public static func - (l: Vec3, r: Vec3) -> Vec3 {
        Vec3(l.x - r.x, l.y - r.y, l.z - r.z)
    }

    public static func * (l: Vec3, s: Double) -> Vec3 {
        Vec3(l.x * s, l.y * s, l.z * s)
    }
}

/// One reading from the motion sensors, plus how long ago the user last typed or clicked.
public struct SensorSample: Equatable, Sendable {
    /// Seconds on a monotonic clock.
    public var time: Double
    /// Acceleration in g.
    public var accel: Vec3
    /// Angular rate when the gyroscope is available, otherwise nil.
    public var gyro: Vec3?
    /// Seconds since the last key press or click. Large when unknown.
    public var inputIdle: Double

    public init(time: Double, accel: Vec3, gyro: Vec3? = nil, inputIdle: Double = 1000) {
        self.time = time
        self.accel = accel
        self.gyro = gyro
        self.inputIdle = inputIdle
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, returning the fallback when the key is missing or malformed.
    /// Used so settings files written by older versions keep loading.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
