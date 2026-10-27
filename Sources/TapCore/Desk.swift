import Foundation

/// A rectangle in points. Kept here so layout maths runs and is tested on any platform.
public struct LayoutRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }
}

/// Where to put the front window on its screen.
public enum WindowPreset: String, CaseIterable, Sendable {
    case leftHalf = "left half"
    case rightHalf = "right half"
    case topHalf = "top half"
    case bottomHalf = "bottom half"
    case leftThird = "left third"
    case middleThird = "middle third"
    case rightThird = "right third"
    case maximize = "maximize"
    case center = "center"

    public static var choices: [String] { allCases.map { $0.rawValue } }

    /// Understands what a person would type: "left", "Left Half", "full screen", "max".
    public static func parse(_ text: String) -> WindowPreset? {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "the ", with: "").replacingOccurrences(of: "-", with: " ")
        if let exact = WindowPreset(rawValue: t) { return exact }
        switch t {
        case "left": return .leftHalf
        case "right": return .rightHalf
        case "top": return .topHalf
        case "bottom": return .bottomHalf
        case "max", "maximise", "maximize", "full", "full screen", "fullscreen", "fill": return .maximize
        case "middle", "centre", "centered", "centred": return .center
        default: return nil
        }
    }

    /// The window frame inside `visible` (the screen area not covered by the menu bar and Dock).
    public func rect(in visible: LayoutRect) -> LayoutRect {
        let w = visible.width, h = visible.height
        switch self {
        case .leftHalf: return LayoutRect(x: visible.x, y: visible.y, width: (w / 2).rounded(.down), height: h)
        case .rightHalf:
            let half = (w / 2).rounded(.down)
            return LayoutRect(x: visible.x + w - half, y: visible.y, width: half, height: h)
        case .topHalf: return LayoutRect(x: visible.x, y: visible.y, width: w, height: (h / 2).rounded(.down))
        case .bottomHalf:
            let half = (h / 2).rounded(.down)
            return LayoutRect(x: visible.x, y: visible.y + h - half, width: w, height: half)
        case .leftThird: return LayoutRect(x: visible.x, y: visible.y, width: (w / 3).rounded(.down), height: h)
        case .middleThird:
            let third = (w / 3).rounded(.down)
            return LayoutRect(x: visible.x + third, y: visible.y, width: third, height: h)
        case .rightThird:
            let third = (w / 3).rounded(.down)
            return LayoutRect(x: visible.x + w - third, y: visible.y, width: third, height: h)
        case .maximize: return visible
        case .center:
            let cw = (w * 0.62).rounded(), ch = (h * 0.72).rounded()
            return LayoutRect(x: (visible.x + (w - cw) / 2).rounded(), y: (visible.y + (h - ch) / 2).rounded(), width: cw, height: ch)
        }
    }
}

/// Window positions saved as fractions of a screen, so a layout survives a change of resolution.
public enum LayoutMath {
    /// Window frame as 0 to 1 fractions of the visible area, clamped so a window half off the screen still saves sensibly.
    public static func fractions(of window: LayoutRect, in visible: LayoutRect) -> LayoutRect {
        guard visible.width > 0, visible.height > 0 else { return LayoutRect(x: 0, y: 0, width: 1, height: 1) }
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        let x = clamp((window.x - visible.x) / visible.width)
        let y = clamp((window.y - visible.y) / visible.height)
        let w = min(clamp(window.width / visible.width), 1 - x)
        let h = min(clamp(window.height / visible.height), 1 - y)
        return LayoutRect(x: x, y: y, width: w, height: h)
    }

    /// Turns saved fractions back into a frame on a screen: whole points, never smaller than `minSize`, never off the screen.
    public static func frame(fractions f: LayoutRect, in visible: LayoutRect, minSize: Double = 120) -> LayoutRect {
        var w = max((f.width * visible.width).rounded(), min(minSize, visible.width))
        var h = max((f.height * visible.height).rounded(), min(minSize, visible.height))
        w = min(w, visible.width)
        h = min(h, visible.height)
        var x = (visible.x + f.x * visible.width).rounded()
        var y = (visible.y + f.y * visible.height).rounded()
        x = min(max(x, visible.x), visible.maxX - w)
        y = min(max(y, visible.y), visible.maxY - h)
        return LayoutRect(x: x, y: y, width: w, height: h)
    }
}

public struct LayoutEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var bundleID: String
    public var appName: String
    /// Which screen it was on: 0 is the main screen, then in the order macOS lists them.
    public var display: Int
    public var fractions: LayoutRect

    public init(id: String = IDs.new(), bundleID: String, appName: String, display: Int = 0, fractions: LayoutRect) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.display = display
        self.fractions = fractions
    }
}

/// A named arrangement of app windows.
public struct DeskLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var entries: [LayoutEntry]

    public init(id: String = IDs.new(), name: String, entries: [LayoutEntry] = []) {
        self.id = id
        self.name = name
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey { case id, name, entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, IDs.new())
        name = c.lenient(.name, "Layout")
        entries = c.lenient(.entries, [LayoutEntry]())
    }

    /// Finds a layout by the name typed in an action. An empty name means the only layout, or the first one.
    public static func find(_ name: String, in layouts: [DeskLayout]) -> DeskLayout? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if wanted.isEmpty { return layouts.first }
        return layouts.first { $0.name.lowercased() == wanted }
    }
}

/// Parsing for the actions that take several things in one box.
public enum ItemList {
    /// Splits on new lines, commas and semicolons, trims, drops empties and repeats, and keeps the order.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for part in text.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" }) {
            let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty, seen.insert(item.lowercased()).inserted { out.append(item) }
        }
        return out
    }
}

/// What "Open files, folders or links" may open. Only web and mail links and absolute paths: nothing else is guessed.
public enum OpenItem: Equatable, Sendable {
    case link(URL)
    case path(String)
    case invalid(String)

    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    public static func classify(_ text: String) -> OpenItem {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("/") || t.hasPrefix("~") {
            return .path((t as NSString).expandingTildeInPath)
        }
        if let url = URL(string: t), let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) {
            if scheme == "mailto" || (url.host?.isEmpty == false) { return .link(url) }
        }
        return .invalid(t)
    }
}
