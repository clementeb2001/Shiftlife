import XCTest
@testable import ShiftLife

/// Unit tests for the core value logic (free-time + conflict detection).
///
/// These are NOT wired into the Xcode project by default so the app target
/// always builds cleanly on a fresh checkout. To run them:
/// 1. In Xcode: File ▸ New ▸ Target… ▸ Unit Testing Bundle (name "ShiftLifeTests").
/// 2. Drag this file into the new test target.
/// 3. Cmd-U.
final class ShiftLifeEngineTests: XCTestCase {

    @MainActor
    private func makeStore() -> AppStore {
        // In-memory store seeded with deterministic sample data.
        AppStore(inMemory: true)
    }

    @MainActor
    func testBusyIntervalsIncludeShift() {
        let store = makeStore()
        let user = store.currentUser
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Force a known early shift today.
        if let frueh = store.data.shiftTypes.first(where: { $0.abbreviation == "F" }) {
            store.setShift(memberID: user.id, typeID: frueh.id, on: today)
            let intervals = store.busyIntervals(for: user.id,
                                                from: today,
                                                to: cal.date(byAdding: .day, value: 1, to: today)!)
            XCTAssertFalse(intervals.isEmpty, "A scheduled shift should produce a busy interval")
        }
    }

    @MainActor
    func testMergeIntervalsCombinesOverlaps() {
        let now = Date()
        let a = (start: now, end: now.addingTimeInterval(3600))
        let b = (start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400))
        let merged = CommonFreeTimeEngine.mergeIntervals([a, b])
        XCTAssertEqual(merged.count, 1, "Overlapping intervals must merge into one")
        XCTAssertEqual(merged.first?.end, b.end)
    }

    @MainActor
    func testFreeWindowRespectsMinimumDuration() {
        let store = makeStore()
        let members = store.data.members.filter { $0.role != .child }.map { $0.id }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let q = FreeTimeQuery(memberIDs: members, rangeStart: now, rangeEnd: end,
                              minimumDurationMinutes: 120)
        let windows = CommonFreeTimeEngine.freeWindows(store: store, query: q)
        XCTAssertTrue(windows.allSatisfy { $0.durationMinutes >= 120 },
                      "Every returned window must meet the minimum duration")
        // Windows must be sorted ascending.
        XCTAssertEqual(windows, windows.sorted { $0.start < $1.start })
    }

    @MainActor
    func testConflictDetectionProducesNoDuplicates() {
        let store = makeStore()
        let conflicts = ConflictEngine.detect(store: store)
        let keys = conflicts.map { "\($0.kind)-\($0.eventID?.uuidString ?? "")-\(Int($0.date.timeIntervalSince1970))" }
        XCTAssertEqual(keys.count, Set(keys).count, "Conflicts must be de-duplicated")
    }

    @MainActor
    func testEmptyMembersReturnsNoWindows() {
        let store = makeStore()
        let q = FreeTimeQuery(memberIDs: [], rangeStart: Date(),
                              rangeEnd: Date().addingTimeInterval(86400))
        XCTAssertTrue(CommonFreeTimeEngine.freeWindows(store: store, query: q).isEmpty)
    }
}
