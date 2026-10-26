import Foundation

enum AppInfo {
    /// Shown in About. Change this when you fork the project.
    static let repositoryURL = "https://github.com/your-name/TapDeck"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }
}
