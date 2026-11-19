import XCTest
@testable import GRAMO_APP

final class MealSessionSyncTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testLostReplyRetriesAndFrequentSavesDoNotReplacePendingID() throws {
        var sync = MealSessionSync()
        let first = try XCTUnwrap(sync.next(meal: "meal-live-1", now: now))
        XCTAssertFalse(sync.ready(for: "meal-live-1"))
        XCTAssertNil(sync.next(meal: "meal-live-1", now: now.addingTimeInterval(1), force: true))
        XCTAssertEqual(sync.pending?.id, first.id)
        let retry = try XCTUnwrap(sync.next(meal: "meal-live-1", now: now.addingTimeInterval(4)))
        XCTAssertNotEqual(retry.id, first.id)
        XCTAssertFalse(sync.acknowledge(id: first.id, active: true, now: now))
        XCTAssertFalse(sync.acknowledge(id: retry.id, active: false, now: now))
        XCTAssertTrue(sync.acknowledge(id: retry.id, active: true, now: now.addingTimeInterval(4)))
        XCTAssertTrue(sync.ready(for: "meal-live-1"))
        XCTAssertNil(sync.next(meal: "meal-live-1", now: now.addingTimeInterval(5)))
    }
    func testEndMealReconnectAndDeviceResetRearm() throws {
        var sync = MealSessionSync()
        let first = try XCTUnwrap(sync.next(meal: "meal-live-1", now: now))
        XCTAssertTrue(sync.acknowledge(id: first.id, active: true, now: now))
        XCTAssertNotNil(sync.next(meal: "meal-live-1", now: now.addingTimeInterval(31)))
        let stop = try XCTUnwrap(sync.next(meal: nil, now: now.addingTimeInterval(32)))
        XCTAssertFalse(sync.ready(for: "meal-live-1"))
        XCTAssertTrue(sync.acknowledge(id: stop.id, active: false, now: now))
        XCTAssertFalse(sync.ready(for: nil))
        sync.reset()
        XCTAssertNotNil(sync.next(meal: "meal-live-1", now: now))
    }
    @MainActor func testPendingButtonSurvivesRelaunchWithoutCameraOrModel() throws {
        let domain = "gramo.button.relaunch.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults)
        let meal = store.ensureIntegrationMeal(), time = Date().addingTimeInterval(1)
        let event = NomiButtonEvent(v: 1, type: "bite", event: "0123456789abcdef-00000001", device: "50F7FAC13DE8", meal: meal, at: time.timeIntervalSince1970 * 1000)
        XCTAssertTrue(store.receiveButton(event, now: time))
        let restored = AppStore(defaults: defaults)
        XCTAssertEqual(restored.todayBiteCount, 1)
        XCTAssertNil(restored.latestIntake?.grams)
        XCTAssertNil(restored.latestIntake?.estimatedKcal)
        XCTAssertTrue(restored.receiveButton(event, now: time))
        XCTAssertEqual(restored.todayBiteCount, 1)
    }
}
