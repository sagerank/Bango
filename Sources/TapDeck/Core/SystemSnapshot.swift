import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import TapCore

/// Reads the facts workflows decide on, at the moment of a gesture. Nothing here needs a permission.
enum SystemSnapshot {
    static func capture(frontmost: String?) -> SystemContext {
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
        return context
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
        parts.append(context.externalDisplays == 0 ? "no external display" : "\(context.externalDisplays) external display\(context.externalDisplays == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
