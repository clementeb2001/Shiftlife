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
    /// Persist a snapshot immediately and synchronously (used by extensions /
    /// App Intents that finish before a debounced save would flush).
    func saveNow(_ data: AppData)
    /// Remove all stored data (GDPR delete).
    func wipe()
}

extension PersistenceProvider {
    func saveNow(_ data: AppData) { save(data) }
}

/// Local, offline-first store: a single JSON file in the shared App Group
/// container (so the widget can read it), falling back to Documents.
final class LocalJSONPersistence: PersistenceProvider {
    private let fileURL: URL
    private var pending: DispatchWorkItem?

    init() {
        fileURL = SharedContainer.storeURL
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

    func saveNow(_ data: AppData) {
        pending?.cancel()
        if let raw = try? JSONEncoder.appEncoder.encode(data) {
            try? raw.write(to: fileURL, options: .atomic)
        }
    }

    func wipe() {
        pending?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
