import XCTest
import UIKit
@testable import GRAMO_APP

final class ButtonIntegrationTests: XCTestCase {
    @MainActor
    func testPhysicalEventCreatesOnePendingRecordAndReplayCannotResurrectDeletion() throws {
        let domain = "nomi.button.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal()
        let now = Date().addingTimeInterval(1)
        var event = NomiButtonEvent(v: 1, type: "bite", event: "0123456789abcdef-00000001", device: "50F7FAC13DE8", meal: meal, at: now.timeIntervalSince1970*1000)
        XCTAssertTrue(store.receiveButton(event, now: now))
        XCTAssertTrue(store.receiveButton(event, now: now))
        XCTAssertEqual(store.state.meals.flatMap(\.foods).count, 1)
        XCTAssertNil(store.latestIntake?.grams); XCTAssertNil(store.latestIntake?.estimatedKcal)
        event.event = "0123456789abcdef-00000002"; event.at += 150
        XCTAssertTrue(store.receiveButton(event, now: now.addingTimeInterval(1)))
        XCTAssertEqual(store.state.meals.flatMap(\.foods).count, 2) // no long dedup window
        store.removeIntake(event.key)
        XCTAssertTrue(store.receiveButton(event, now: now.addingTimeInterval(1)))
        XCTAssertEqual(store.state.meals.flatMap(\.foods).count, 1)
        store.endMeal(mealId: meal)
        event.event = "0123456789abcdef-00000003"; event.at = Date().addingTimeInterval(30).timeIntervalSince1970*1000
        XCTAssertTrue(store.receiveButton(event, now: Date().addingTimeInterval(31)))
        XCTAssertEqual(store.state.meals.flatMap(\.foods).count, 1) // post-meal press ignored
    }
    @MainActor
    func testFramesAndUnknownSessionsNeverCreateBites() throws {
        let domain = "nomi.button.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults)
        let event = NomiButtonEvent(v: 1, type: "bite", event: "0123456789abcdef-00000001", device: "50F7FAC13DE8", meal: "meal-live-unknown", at: Date().timeIntervalSince1970*1000)
        XCTAssertTrue(store.receiveButton(event))
        XCTAssertTrue(store.state.meals.flatMap(\.foods).isEmpty)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8,height: 8)).image { c in UIColor.gray.setFill(); c.fill(CGRect(x: 0,y: 0,width: 8,height: 8)) }
        XCTAssertTrue(store.receiveFrame(SpoonCameraFrame(id: UUID(),data: image.jpegData(compressionQuality: 0.9)!,timestamp: Date(),deviceID: event.device)))
        XCTAssertTrue(store.state.meals.flatMap(\.foods).isEmpty)
        store.refreshDay(now: Date().addingTimeInterval(7))
        XCTAssertTrue(store.cameraStatus.contains("中断"))
    }
    func testMalformedButtonEventAndLongTypeRejected() {
        var event = NomiButtonEvent(v: 1, type: "long", event: "0123456789abcdef-00000001", device: "50F7FAC13DE8", meal: "meal-live-1", at: 1_800_000_000_000)
        XCTAssertFalse(event.valid)
        event.type = "bite"; XCTAssertTrue(event.valid)
        event.event = "../../escape"; XCTAssertFalse(event.valid)
        event.event = "0123456789abcdef-00000001"; event.at = .nan; XCTAssertFalse(event.valid)
    }
}
