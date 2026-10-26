import Foundation

/// Everything the app saves.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    public var detector: DetectorConfig
    public var profiles: [Profile]
    public var activeProfileID: String
    public var zoneModel: ZoneModel?
    public var monitoringEnabled: Bool
    /// While in the future, actions are logged but not executed.
    public var dryRunEndsAt: Date?
    public var hasCompletedOnboarding: Bool
    public var showHUD: Bool
    public var waveformGain: Double

    public init() {
        let profiles = DefaultProfiles.make()
        self.schemaVersion = Self.currentSchema
        self.detector = DetectorConfig()
        self.profiles = profiles
        self.activeProfileID = profiles[0].id
        self.zoneModel = nil
        self.monitoringEnabled = true
        self.dryRunEndsAt = nil
        self.hasCompletedOnboarding = false
        self.showHUD = true
        self.waveformGain = 3.0
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, detector, profiles, activeProfileID, zoneModel, monitoringEnabled
        case dryRunEndsAt, hasCompletedOnboarding, showHUD, waveformGain
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        schemaVersion = c.lenient(.schemaVersion, d.schemaVersion)
        detector = c.lenient(.detector, d.detector)
        let decodedProfiles: [Profile] = c.lenient(.profiles, d.profiles)
        profiles = decodedProfiles.isEmpty ? d.profiles : decodedProfiles
        let storedActive: String = c.lenient(.activeProfileID, "")
        activeProfileID = profiles.contains(where: { $0.id == storedActive }) ? storedActive : profiles[0].id
        zoneModel = try? c.decodeIfPresent(ZoneModel.self, forKey: .zoneModel)
        monitoringEnabled = c.lenient(.monitoringEnabled, d.monitoringEnabled)
        dryRunEndsAt = try? c.decodeIfPresent(Date.self, forKey: .dryRunEndsAt)
        hasCompletedOnboarding = c.lenient(.hasCompletedOnboarding, d.hasCompletedOnboarding)
        showHUD = c.lenient(.showHUD, d.showHUD)
        waveformGain = c.lenient(.waveformGain, d.waveformGain)
    }

    public var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    /// Edit the active profile in place.
    public mutating func updateActiveProfile(_ change: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        change(&profiles[index])
    }

    public func isDryRun(now: Date = Date()) -> Bool {
        guard let end = dryRunEndsAt else { return false }
        return now < end
    }

    public mutating func startDryRun(hours: Double = 24, now: Date = Date()) {
        dryRunEndsAt = now.addingTimeInterval(hours * 3600)
    }

    public mutating func endDryRun() {
        dryRunEndsAt = nil
    }

    public func pipelineConfig() -> PipelineConfig {
        PipelineConfig(
            detector: detector.normalized(),
            rhythms: activeProfile.rhythms,
            zones: zoneModel
        )
    }
}
