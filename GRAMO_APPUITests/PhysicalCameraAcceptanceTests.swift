import XCTest

/// Opt-in real camera test. Does not reset data, simulate frames or generate bites.
final class PhysicalCameraAcceptanceTests: XCTestCase {
    func testLiveSpoonPreview() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the physical spoon camera")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRAMO_CAMERA_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-camera-acceptance"]
        app.launch()
        let image = app.images["spoon-preview-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 45))
        let time = app.staticTexts["spoon-preview-time"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        let initial = try XCTUnwrap(time.value as? String)
        let changed = NSPredicate { _, _ in
            guard let current = time.value as? String else { return false }
            return current != initial
        }
        expectation(for: changed, evaluatedWith: time)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(image.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "real-spoon-camera-preview"; shot.lifetime = .keepAlways; add(shot)
        #endif
    }
}
