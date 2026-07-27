import Foundation
import CloudKit

/// iCloud (CloudKit) family sync – prepared, opt-in, off by default.
///
/// Design: the whole `AppData` is mirrored as a single record ("AppState") in a
/// custom zone of the user's **private** CloudKit database. The zone is shared
/// with the partner via `CKShare`, so both devices read/write the same state.
/// Conflicts are resolved last-writer-wins by `AppData.updatedAt`.
///
/// IMPORTANT: this never runs while `store.data.syncEnabled == false`, so the
/// app stays 100 % local until iCloud is switched on. Activating it needs the
/// iCloud/CloudKit capability enabled in Xcode on a Mac (see CLOUDKIT.md); it
/// cannot be exercised in the simulator/CI, so the flow must be verified on a
/// real device.
final class CloudSync {
    static let shared = CloudSync()
    static let containerID = "iCloud.com.shiftlife.app"

    // Created lazily: instantiating CKContainer requires the iCloud/CloudKit
    // entitlement and crashes without it. Sync is off by default and every code
    // path guards on `isActive`, so the container is only ever built once the
    // capability is enabled and the user turns sync on – never at app launch.
    private lazy var container = CKContainer(identifier: Self.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "ShiftLifeZone", ownerName: CKCurrentUserDefaultName)
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: "appState", zoneID: zoneID) }
    private let recordType = "AppState"

    private weak var store: AppStore?
    private var pushTask: Task<Void, Never>?
    private(set) var isActive = false

    private init() {}

    // MARK: Lifecycle

    /// Activates sync for a store **iff** the user enabled it. No-ops otherwise,
    /// so it is always safe to call on launch.
    func startIfEnabled(_ store: AppStore) {
        guard store.data.syncEnabled, !isActive else { return }
        self.store = store
        isActive = true
        store.onLocalChange = { [weak self] data in self?.schedulePush(data) }
        Task { await bootstrap() }
    }

    func stop() {
        isActive = false
        store?.onLocalChange = nil
        pushTask?.cancel()
        pushTask = nil
    }

    /// Pulls the latest remote state (call on foreground / on push notification).
    func refresh() {
        guard isActive else { return }
        Task { try? await pull() }
    }

    // MARK: Sync core

    private func bootstrap() async {
        do {
            try await ensureZone()
            try await pull()
            await subscribe()
        } catch {
            NSLog("CloudSync bootstrap error: \(error.localizedDescription)")
        }
    }

    private func ensureZone() async throws {
        _ = try? await database.save(CKRecordZone(zoneID: zoneID))
    }

    private func pull() async throws {
        guard let store else { return }
        do {
            let record = try await database.record(for: recordID)
            if let blob = record["blob"] as? Data,
               let remote = try? JSONDecoder.appDecoder.decode(AppData.self, from: blob) {
                await MainActor.run { store.applyRemote(remote) }
            }
        } catch let e as CKError where e.code == .unknownItem {
            // Nothing in iCloud yet – seed it with our current state.
            schedulePush(store.data)
        }
    }

    private func schedulePush(_ data: AppData) {
        guard isActive else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)   // debounce bursts
            guard !Task.isCancelled else { return }
            await self?.push(data)
        }
    }

    private func push(_ data: AppData) async {
        guard let blob = try? JSONEncoder.appEncoder.encode(data) else { return }
        do {
            let record = (try? await database.record(for: recordID))
                ?? CKRecord(recordType: recordType, recordID: recordID)

            // Conflict guard: if the server copy is newer, adopt it instead of
            // overwriting the partner's more recent change.
            if let existing = record["blob"] as? Data,
               let remote = try? JSONDecoder.appDecoder.decode(AppData.self, from: existing),
               remote.updatedAt > data.updatedAt {
                if let store { await MainActor.run { store.applyRemote(remote) } }
                return
            }

            record["blob"] = blob as CKRecordValue
            record["updatedAt"] = data.updatedAt as CKRecordValue
            _ = try await database.save(record)
        } catch {
            NSLog("CloudSync push error: \(error.localizedDescription)")
        }
    }

    private func subscribe() async {
        let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "shiftlife-zone-sub")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true    // silent background push
        sub.notificationInfo = info
        _ = try? await database.save(sub)
    }

    // MARK: Sharing (invite the partner)

    /// Creates (or fetches) a share for the sync zone so the partner can be
    /// invited. The app presents it with `UICloudSharingController`.
    func prepareShare() async throws -> (CKShare, CKContainer) {
        try await ensureZone()
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "ShiftLife" as CKRecordValue
        let saved = try await database.save(share)
        return (saved as? CKShare ?? share, container)
    }
}
