import Foundation
import IOKit
import IOKit.hid
import TapCore

/// Which motion sensor a report came from.
enum SensorKind {
    case accelerometer
    case gyroscope

    /// HID usage on the Apple vendor page (0xFF00).
    var usage: Int {
        switch self {
        case .accelerometer: return 3
        case .gyroscope: return 9
        }
    }
}

enum SensorError: LocalizedError {
    case unavailable
    case openFailed(status: kern_return_t)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "No built-in accelerometer was found on this Mac."
        case .openFailed(let status):
            return "The accelerometer could not be opened (code \(status))."
        }
    }
}

/// Reads the built-in motion sensors of Apple Silicon MacBooks through IOKit HID.
///
/// The accelerometer is required. The gyroscope is optional: when it is missing, samples carry
/// no gyro data and tap zones stay unavailable. Everything else keeps working.
///
/// The report layout (22 bytes, signed 32 bit little endian values in Q16.16 at offset 6) was
/// worked out by the open source community. Apple does not document it, so it may change
/// between macOS releases.
final class SensorService {
    private static let vendorUsagePage = 0xFF00
    private static let reportLength = 22
    private static let payloadOffset = 6
    private static let scale = 65536.0
    static let bufferSize = 4096
    /// A gyro reading older than this is not attached to an accelerometer sample.
    private static let gyroMaxAge = 0.05

    /// Called on the sensor queue for every accelerometer report.
    var onSample: (@Sendable (SensorSample) -> Void)?

    private let queue = DispatchQueue(label: "app.bango.sensors", qos: .userInteractive)
    private var handles: [Handle] = []
    private var running = false
    private(set) var hasGyroscope = false

    // Latest gyro reading. Only touched on `queue`.
    private var lastGyro = Vec3.zero
    private var lastGyroTime = -Double.infinity

    /// Input idle provider, set by the owner. Called on the sensor queue.
    var inputIdle: @Sendable () -> Double = { 1000 }

    func accelerometerAvailable() -> Bool {
        let services = matchingServices(for: .accelerometer)
        let found = !services.isEmpty
        services.forEach { IOObjectRelease($0) }
        return found
    }

    func start() throws {
        guard !running else { return }
        wakeDrivers()

        let accelServices = matchingServices(for: .accelerometer)
        guard !accelServices.isEmpty else { throw SensorError.unavailable }
        let gyroServices = matchingServices(for: .gyroscope)

        var opened: [Handle] = []
        do {
            for service in accelServices {
                if let handle = try open(service: service, kind: .accelerometer) { opened.append(handle) }
            }
            for service in gyroServices {
                // The gyroscope is a bonus. A failure to open it must not stop the accelerometer.
                if let handle = try? open(service: service, kind: .gyroscope) { opened.append(handle) }
            }
        } catch {
            opened.forEach { $0.stop() }
            throw error
        }

        guard opened.contains(where: { $0.kind == .accelerometer }) else {
            opened.forEach { $0.stop() }
            throw SensorError.unavailable
        }

        handles = opened
        hasGyroscope = opened.contains(where: { $0.kind == .gyroscope })
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        handles.forEach { $0.stop() }
        handles.removeAll()
        hasGyroscope = false
    }

    // MARK: - Opening devices

    /// Takes ownership of `service` and releases it.
    private func open(service: io_service_t, kind: SensorKind) throws -> Handle? {
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return nil }
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw SensorError.openFailed(status: status) }
        let handle = Handle(device: device, kind: kind, owner: self)
        handle.activate(queue: queue)
        return handle
    }

    // MARK: - Reports

    fileprivate func handleReport(kind: SensorKind, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard running, length == Self.reportLength else { return }

        let x = Double(Self.int32LE(report, Self.payloadOffset)) / Self.scale
        let y = Double(Self.int32LE(report, Self.payloadOffset + 4)) / Self.scale
        let z = Double(Self.int32LE(report, Self.payloadOffset + 8)) / Self.scale
        let now = ProcessInfo.processInfo.systemUptime

        switch kind {
        case .gyroscope:
            lastGyro = Vec3(x, y, z)
            lastGyroTime = now
        case .accelerometer:
            let gyro: Vec3? = (now - lastGyroTime) <= Self.gyroMaxAge ? lastGyro : nil
            onSample?(SensorSample(time: now, accel: Vec3(x, y, z), gyro: gyro, inputIdle: inputIdle()))
        }
    }

    private static func int32LE(_ p: UnsafeMutablePointer<UInt8>, _ offset: Int) -> Int32 {
        let b0 = UInt32(p[offset])
        let b1 = UInt32(p[offset + 1]) << 8
        let b2 = UInt32(p[offset + 2]) << 16
        let b3 = UInt32(p[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }

    // MARK: - IOKit helpers

    private func wakeDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 1000 as CFNumber)
            IOObjectRelease(service)
        }
    }

    private func matchingServices(for kind: SensorKind) -> [io_service_t] {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var matches: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            let page = Self.intProperty(service, "PrimaryUsagePage")
            let usage = Self.intProperty(service, "PrimaryUsage")
            if page == Self.vendorUsagePage, usage == kind.usage {
                matches.append(service)
            } else {
                IOObjectRelease(service)
            }
        }
        return matches
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return nil }
        return (value as? NSNumber)?.intValue
    }

    // MARK: - Per device state

    private final class Handle {
        let device: IOHIDDevice
        let kind: SensorKind
        let buffer: UnsafeMutablePointer<UInt8>
        private weak var owner: SensorService?

        init(device: IOHIDDevice, kind: SensorKind, owner: SensorService) {
            self.device = device
            self.kind = kind
            self.owner = owner
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: SensorService.bufferSize)
        }

        deinit { buffer.deallocate() }

        private static let callback: IOHIDReportWithTimeStampCallback = { context, _, _, _, _, report, length, _ in
            guard let context else { return }
            let handle = Unmanaged<Handle>.fromOpaque(context).takeUnretainedValue()
            handle.owner?.handleReport(kind: handle.kind, report: report, length: length)
        }

        func activate(queue: DispatchQueue) {
            IOHIDDeviceSetDispatchQueue(device, queue)
            IOHIDDeviceRegisterInputReportWithTimeStampCallback(
                device,
                buffer,
                SensorService.bufferSize,
                Self.callback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            IOHIDDeviceActivate(device)
        }

        func stop() {
            IOHIDDeviceCancel(device)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
