import AppKit
import CoreAudio
import CoreGraphics
import CoreWLAN
import Foundation
import IOBluetooth
import IOKit
import IOKit.ps
import TapCore

/// Reads the facts workflows decide on, at the moment of a gesture. Nothing here asks for a permission.
/// Devices, Wi-Fi and Bluetooth are only read when a condition in the workflow uses them, so a workflow that does
/// not care about Bluetooth never touches it.
enum SystemSnapshot {
    static func capture(
        frontmost: String?,
        needing kinds: Set<WorkflowCondition.Kind> = Set(WorkflowCondition.Kind.allCases)
    ) -> SystemContext {
        var context = SystemContext(now: Date(), bootDate: bootDate())
        context.frontmostBundleID = frontmost
        context.runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let power = powerState()
        context.onBattery = power.onBattery
        context.batteryPercent = power.percent
        context.externalDisplays = NSScreen.screens.filter { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) == 0
        }.count
        if kinds.contains(.wifiOn) || kinds.contains(.wifiConnected) {
            let wifi = wifiState()
            context.wifiOn = wifi.on
            context.wifiConnected = wifi.connected
        }
        if kinds.contains(.bluetoothOn) || kinds.contains(.bluetoothDevice) {
            let bluetooth = bluetoothState()
            context.bluetoothOn = bluetooth.on
            context.bluetoothDevices = bluetooth.connected
        }
        if kinds.contains(.usbDevice) { context.usbDevices = usbDevices() }
        if kinds.contains(.audioOutput) { context.audioOutput = defaultAudioOutputName() }
        if kinds.contains(.lowPowerMode) { context.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        return context
    }

    // MARK: - Devices

    private static func wifiState() -> (on: Bool?, connected: Bool?) {
        guard let interface = CWWiFiClient.shared().interface() else { return (nil, nil) }
        let on = interface.powerOn()
        guard on, let name = interface.interfaceName else { return (on, false) }
        // The network name needs Location access, so "connected" means the Wi-Fi interface holds an address.
        return (on, hasIPv4Address(on: name))
    }

    private static func hasIPv4Address(on name: String) -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let item = entry.pointee
            if String(cString: item.ifa_name) == name, let address = item.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET)
            {
                return true
            }
            cursor = item.ifa_next
        }
        return false
    }

    private static func bluetoothState() -> (on: Bool?, connected: [String]) {
        guard let controller = IOBluetoothHostController.default() else { return (nil, []) }
        guard controller.powerState == kBluetoothHCIPowerStateON else { return (false, []) }
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return (true, paired.filter { $0.isConnected() }.compactMap { $0.name })
    }

    private static func pairedBluetoothNames() -> [String] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { $0.name }
    }

    private static func usbDevices() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var names: [String] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let name = IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            {
                names.append(name)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return Array(Set(names)).sorted()
    }

    private static func defaultAudioOutputName() -> String? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown
        else { return nil }
        return audioDeviceName(id)
    }

    private static func audioDeviceName(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func audioOutputNames() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { hasOutput($0) ? audioDeviceName($0) : nil }
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    /// Names to offer in the editor's "Choose" menu: what is connected or available right now.
    static func deviceNames(for kind: WorkflowCondition.Kind) -> [String] {
        switch kind {
        case .bluetoothDevice: return Array(Set(pairedBluetoothNames())).sorted()
        case .usbDevice: return usbDevices()
        case .audioOutput: return Array(Set(audioOutputNames())).sorted()
        default: return []
        }
    }

    /// When the Mac was started, including time spent asleep.
    private static func bootDate() -> Date? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(boot.tv_sec))
    }

    private static func powerState() -> (onBattery: Bool?, percent: Double?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, nil) }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let percent = (current != nil && (maximum ?? 0) > 0) ? current! / maximum! * 100 : current
            return (state.map { $0 == kIOPSBatteryPowerValue }, percent)
        }
        return (nil, nil) // a Mac without a battery
    }

    /// The facts in plain words, so a person can see why a workflow chose what it chose.
    static func facts(_ context: SystemContext) -> String {
        var parts: [String] = []
        parts.append("time \(WorkflowCondition.clock(context.minutesSinceMidnight))")
        if let boot = context.minutesSinceBoot { parts.append("started \(Int(boot)) minutes ago") }
        if let battery = context.onBattery {
            let level = context.batteryPercent.map { ", \(Int($0))%" } ?? ""
            parts.append(battery ? "on battery\(level)" : "plugged in\(level)")
        } else {
            parts.append("no battery found")
        }
        if let on = context.wifiOn { parts.append(on ? (context.wifiConnected == true ? "Wi-Fi connected" : "Wi-Fi on, not connected") : "Wi-Fi off") }
        if let on = context.bluetoothOn {
            parts.append(on ? (context.bluetoothDevices.isEmpty ? "Bluetooth on, nothing connected" : "Bluetooth: \(context.bluetoothDevices.joined(separator: ", "))") : "Bluetooth off")
        }
        if !context.usbDevices.isEmpty { parts.append("USB: \(context.usbDevices.joined(separator: ", "))") }
        if let output = context.audioOutput { parts.append("sound to \(output)") }
        if let lowPower = context.lowPowerMode { parts.append(lowPower ? "Low Power Mode on" : "Low Power Mode off") }
        parts.append(context.externalDisplays == 0 ? "no external display" : "\(context.externalDisplays) external display\(context.externalDisplays == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
