import Foundation

/// Abstraction over where ShiftLife data is stored and synced.
///
/// Today only `LocalJSONPersistence` exists (everything on-device, no account).
/// This protocol is the seam for the planned two-device sharing (see CLOUDKIT.md):
/// a future `CloudKitPersistence` can conform to the same protocol, so switching
/// from "just me" to "me + partner, live-synced" is a provider swap – not a rewrite.
protocol PersistenceProvider {
    /// Load the persisted data, or nil if nothing is stored yet.
    func load() -> AppData?
    /// Persist a snapshot (may be debounced/async internally).
    func save(_ data: AppData)
    /// Remove all stored data (GDPR delete).
    func wipe()
}

/// Local, offline-first store: a single JSON file in the app's Documents dir.
final class LocalJSONPersistence: PersistenceProvider {
    private let fileURL: URL
    private var pending: DispatchWorkItem?

    init(filename: String = "shiftlife_data.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent(filename)
    }

    func load() -> AppData? {
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.appDecoder.decode(AppData.self, from: raw)
    }

    func save(_ data: AppData) {
        pending?.cancel()
        let url = fileURL
        let work = DispatchWorkItem {
            if let raw = try? JSONEncoder.appEncoder.encode(data) {
                try? raw.write(to: url, options: .atomic)
            }
        }
        pending = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func wipe() {
        pending?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
