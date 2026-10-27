import Foundation

/// Decides which running copies of the app must close when another one starts.
public enum InstancePolicy {
    public struct Copy: Equatable, Sendable {
        public var pid: Int32
        public var launched: Double

        public init(pid: Int32, launched: Double) {
            self.pid = pid
            self.launched = launched
        }

        /// Older launch first. Equal launch times fall back to the process number, so two copies that
        /// start in the same instant still agree on which one is older.
        func isOlder(than other: Copy) -> Bool {
            launched != other.launched ? launched < other.launched : pid < other.pid
        }
    }

    /// The copies `me` should close: only older ones. A newer copy will close `me` on its own, so two
    /// copies starting together never close each other, and the newest one always survives.
    public static func copiesToClose(me: Copy, others: [Copy]) -> [Copy] {
        others.filter { $0.pid != me.pid && $0.isOlder(than: me) }
    }
}
