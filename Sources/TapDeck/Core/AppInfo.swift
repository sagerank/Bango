import Foundation

enum AppInfo {
    /// Shown in About. Change this when you fork the project.
    static let repositoryURL = "https://github.com/sagerank/bango"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }
}
