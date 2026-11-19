import XCTest

/// Explicit opt-in lab test. Uses real storage and requires two human short presses.
/// TEST_RUNNER_GRAMO_HARDWARE_ACCEPTANCE=1 xcodebuild ... -only-testing:GRAMO_APPUITests/PhysicalButtonAcceptanceTests
final class PhysicalButtonAcceptanceTests: XCTestCase {
    func testTwoPhysicalPresses() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the physical spoon and iPhone")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRAMO_HARDWARE_ACCEPTANCE"] == "1", "Real-hardware test is opt-in")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-language", "en"] // No mock, reset or isolated UI-testing store.
        app.launch()
        XCTAssertTrue(app.buttons["device-chip"].waitForExistence(timeout: 10))
        app.buttons["device-chip"].tap()
        let connect = app.buttons["device-primary"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5)); connect.tap()
        let spoon = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "NOMI01")).firstMatch
        XCTAssertTrue(spoon.waitForExistence(timeout: 25)); spoon.tap()
        let done = app.buttons["connection-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        if !done.isHittable { app.swipeUp() }
        done.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["start-meal"].waitForExistence(timeout: 5)); app.buttons["start-meal"].tap()
        let begin = app.buttons["begin-recording"]
        if begin.waitForExistence(timeout: 2) { begin.tap() }
        let status = app.staticTexts["button-recording-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label == %@", "After each bite, press your spoon to record it.")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        print("PHYSICAL_BUTTON_STATUS " + status.label)
        let count = app.staticTexts["meal-bite-count"]
        let initial = try XCTUnwrap(Int(count.label))
        print("PHYSICAL_BUTTON_BASELINE \(initial)")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "physical-button-ready"; attachment.lifetime = .keepAlways; add(attachment)
        expectation(for: NSPredicate(format: "label == %@", String(initial + 2)), evaluatedWith: count)
        waitForExpectations(timeout: 180)
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "physical-two-presses"; after.lifetime = .keepAlways; add(after)
        #endif
    }
}
