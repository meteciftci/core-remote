import Foundation

nonisolated extension Bundle {
    static let releaseNotesURL = URL(string: "https://github.com/meteciftci/core-remote/releases")!

    /// "1.4.0 (8)", from Info.plist.
    var versionDescription: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return version }
        return "\(version) (\(build))"
    }
}
