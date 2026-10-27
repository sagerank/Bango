import AppKit
import CoreGraphics

/// Sends key presses and media keys, as if typed on the keyboard. Needs the Accessibility permission.
enum KeyPoster {
    /// Virtual key codes (ANSI layout positions, so shortcuts work on every keyboard language).
    enum Code {
        static let a: CGKeyCode = 0
        static let z: CGKeyCode = 6
        static let x: CGKeyCode = 7
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
        static let h: CGKeyCode = 4
        static let q: CGKeyCode = 12
        static let three: CGKeyCode = 20
        static let four: CGKeyCode = 21
        static let five: CGKeyCode = 23
        static let space: CGKeyCode = 49
        static let f11: CGKeyCode = 103
        static let brightnessUp: CGKeyCode = 144
        static let brightnessDown: CGKeyCode = 145
    }

    /// Media key identifiers used by the system (NX_KEYTYPE values).
    enum MediaKey: Int32 {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
    }

    static func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func media(_ key: MediaKey) {
        post(key: key.rawValue, down: true)
        post(key: key.rawValue, down: false)
    }

    private static func post(key: Int32, down: Bool) {
        let state: Int = down ? 0xA : 0xB
        let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
        let data1 = Int((key << 16)) | (state << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
