import Foundation

/// Locates the on-device store file. When the App Group is provisioned (on a
/// real device / TestFlight) the file lives in the shared container so the
/// widget extension can read the same data as the app. Until then – e.g. in the
/// simulator or CI without signing – it falls back to the app's Documents dir,
/// so the app keeps working unchanged.
enum SharedContainer {
    /// App Group identifier shared between the app and its widget extension.
    static let appGroupID = "group.com.shiftlife.app"

    static let storeFilename = "shiftlife_data.json"

    /// Directory that both the app and the widget can read/write.
    static var directory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var storeURL: URL {
        directory.appendingPathComponent(storeFilename)
    }
}
