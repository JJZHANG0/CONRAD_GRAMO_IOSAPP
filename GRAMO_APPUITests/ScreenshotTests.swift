import XCTest

final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(mock: Bool = false, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-language", "zh", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans"]
        if reset { app.launchArguments += ["-reset-ui-testing"] }
        if mock { app.launchArguments += ["-mock-device"]; if reset { app.launchArguments += ["-reset-simulation"] } }
        app.launch(); XCTAssertTrue(app.buttons["start-meal"].waitForExistence(timeout: 8)); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable,"Missing element: \(element)")
    }
    private func openControls(_ app: XCUIApplication) {
        app.buttons["start-meal"].tap()
        XCTAssertTrue(app.buttons["open-mock-controls"].waitForExistence(timeout: 5))
        reveal(app.buttons["open-mock-controls"],in: app); app.buttons["open-mock-controls"].tap()
        XCTAssertTrue(app.buttons["mock-connect"].waitForExistence(timeout: 4))
    }
    private func totals(_ app: XCUIApplication,_ text: String) {
        for _ in 0..<4 { if app.staticTexts["mock-totals"].exists { break }; app.swipeDown() }
        let predicate = NSPredicate(format:"label == %@",text)
        expectation(for: predicate,evaluatedWith: app.staticTexts["mock-totals"])
        waitForExpectations(timeout: 5)
    }
    private func shot(_ app: XCUIApplication,_ name: String) {
        let file = XCTAttachment(screenshot: app.screenshot()); file.name = name; file.lifetime = .keepAlways; add(file)
    }
    func testConsumerPagesHideDevelopmentInformation() {
        let app = launch()
        XCTAssertFalse(app.staticTexts["simulation-banner"].exists)
        shot(app,"product-home")
        app.tabBars.buttons["记录"].tap(); XCTAssertTrue(app.buttons["records-calendar"].waitForExistence(timeout: 3)); shot(app,"product-records-empty")
        app.tabBars.buttons["趋势"].tap(); XCTAssertTrue(app.staticTexts["看见自己的节奏"].waitForExistence(timeout: 3)); shot(app,"product-insights-empty")
        app.tabBars.buttons["我的"].tap(); XCTAssertTrue(app.buttons["profile-device"].waitForExistence(timeout: 3)); shot(app,"product-profile")
        app.swipeUp(); app.swipeUp()
        XCTAssertFalse(app.buttons["open-debug"].exists)
        for word in ["GATT", "UUID", "串口", "联调", "原始传感器", "置信度"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@",word)).firstMatch.exists)
        }
        reveal(app.buttons["profile-privacy"],in: app); app.buttons["profile-privacy"].tap()
        XCTAssertTrue(app.buttons["prepare-export"].waitForExistence(timeout: 3))
    }
    func testMockPressReplayPowerHistoryAndRelaunch() {
        let app = launch(mock: true)
        openControls(app)
        app.buttons["mock-connect"].tap(); app.buttons["mock-start-meal"].tap()
        app.buttons["mock-short"].tap(); totals(app,"1 口 · 10 kcal · 0 口待完善")
        app.buttons["mock-replay"].tap(); totals(app,"1 口 · 10 kcal · 0 口待完善")
        app.buttons["mock-short"].tap(); totals(app,"2 口 · 20 kcal · 0 口待完善")
        app.buttons["mock-long"].tap(); app.buttons["mock-short"].tap(); totals(app,"2 口 · 20 kcal · 0 口待完善")
        XCTAssertTrue(app.staticTexts["mock-device-status"].label.contains("电源：关"))
        app.buttons["mock-long"].tap(); totals(app,"2 口 · 20 kcal · 0 口待完善")
        app.buttons["mock-disconnect"].tap(); app.buttons["mock-short"].tap(); totals(app,"2 口 · 20 kcal · 0 口待完善")
        XCTAssertTrue(app.staticTexts["mock-device-status"].label.contains("队列：1"))
        app.buttons["mock-connect"].tap(); totals(app,"3 口 · 30 kcal · 0 口待完善")
        shot(app,"mock-event-validation")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["meal-bite-count"].label,"3")
        shot(app,"product-active-meal")
        app.buttons["收起"].tap()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.otherElements["records-summary"].exists || app.staticTexts["进食记录"].exists)
        let meal = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'meal-meal-live-'")).firstMatch
        reveal(meal,in: app); meal.tap()
        XCTAssertTrue(app.staticTexts["每一口，都在这里"].waitForExistence(timeout: 3)); shot(app,"product-meal-detail")
        app.terminate()
        let reopened = launch(mock: true,reset: false)
        openControls(reopened); totals(reopened,"3 口 · 30 kcal · 0 口待完善")
        reopened.buttons["mock-connect"].tap(); reopened.buttons["mock-replay"].tap(); totals(reopened,"3 口 · 30 kcal · 0 口待完善")
    }
    func testMockMissingEvidenceAndThreshold() {
        let app = launch(mock: true); openControls(app)
        app.buttons["mock-connect"].tap(); app.buttons["mock-start-meal"].tap()
        reveal(app.buttons["mock-goal"],in: app); app.buttons["mock-goal"].tap()
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts["mock-device-status"].label.contains("模拟灯：绿"))
        app.buttons["mock-short"].tap(); app.buttons["mock-short"].tap()
        totals(app,"2 口 · 20 kcal · 0 口待完善")
        XCTAssertTrue(app.staticTexts["mock-device-status"].label.contains("模拟灯：红"))
        let toggle = app.switches["mock-portion"]; reveal(toggle,in: app); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93,dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"0")
        app.swipeDown(); app.swipeDown()
        app.buttons["mock-short"].tap(); totals(app,"3 口 · 20 kcal · 1 口待完善")
        shot(app,"mock-missing-evidence")
    }
    func testGoalProfileAndManualDishFlow() {
        let app = launch(mock: true)
        app.buttons["home-goal"].tap()
        let field = app.textFields["daily-goal-input"]; XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("1800")
        app.buttons["save-goal"].tap()
        XCTAssertTrue(app.buttons["start-meal"].waitForExistence(timeout: 3))
        app.buttons["start-meal"].tap(); app.buttons["select-current-dish"].tap()
        let name = app.textFields["dish-name"]; XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("番茄炒蛋")
        app.buttons["confirm-dish"].tap()
        XCTAssertTrue(app.buttons["select-current-dish"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["select-current-dish"].label.contains("番茄炒蛋"))
        app.buttons["收起"].tap(); app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["profile-goal"].label.contains("1800"))
        shot(app,"product-profile-goal")
    }
    func testEditingDeletingAndReplayUseTheSameRecord() {
        let app = launch(mock: true); openControls(app)
        app.buttons["mock-connect"].tap(); app.buttons["mock-start-meal"].tap()
        app.buttons["mock-short"].tap(); app.buttons["mock-short"].tap()
        totals(app,"2 口 · 20 kcal · 0 口待完善")
        app.buttons["完成"].firstMatch.tap()
        let latest = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'bite-'")).firstMatch
        reveal(latest,in: app); latest.tap()
        let grams = app.textFields["bite-grams"]
        XCTAssertTrue(grams.waitForExistence(timeout: 3)); grams.tap()
        grams.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 12)+"2")
        reveal(app.buttons["save-bite"],in: app); app.buttons["save-bite"].tap()
        reveal(app.buttons["open-mock-controls"],in: app); app.buttons["open-mock-controls"].tap()
        totals(app,"2 口 · 12 kcal · 0 口待完善")
        app.buttons["mock-replay"].tap(); totals(app,"2 口 · 12 kcal · 0 口待完善")
        app.buttons["完成"].firstMatch.tap(); reveal(latest,in: app); latest.tap()
        reveal(app.buttons["delete-bite"],in: app); app.buttons["delete-bite"].tap()
        app.alerts.buttons["删除"].tap()
        reveal(app.buttons["open-mock-controls"],in: app); app.buttons["open-mock-controls"].tap()
        totals(app,"1 口 · 10 kcal · 0 口待完善")
        app.buttons["mock-replay"].tap(); totals(app,"1 口 · 10 kcal · 0 口待完善")
    }

    func testDefaultEnglishLanguageSwitchAndPersistence() {
        func openApp(reset: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-mock-device", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans"]
            if reset { app.launchArguments += ["-reset-ui-testing", "-reset-simulation"] }
            app.launch()
            XCTAssertTrue(app.buttons["start-meal"].waitForExistence(timeout: 8))
            return app
        }
        let app = openApp(reset: true)
        XCTAssertTrue(app.staticTexts["Every bite counts."].exists)
        shot(app,"bilingual-home-en")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Your meals, remembered"].waitForExistence(timeout: 3))
        shot(app,"bilingual-records-en")
        app.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Find your rhythm"].waitForExistence(timeout: 3))
        shot(app,"bilingual-trends-en")
        app.tabBars.buttons["Profile"].tap()
        shot(app,"bilingual-profile-en")
        reveal(app.buttons["profile-language"],in: app); app.buttons["profile-language"].tap()
        XCTAssertTrue(app.buttons["language-zh"].waitForExistence(timeout: 3))
        app.buttons["language-zh"].tap()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 3))
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["每一口，都算数。"].exists)
        shot(app,"bilingual-home-zh")
        app.terminate()
        let reopened = openApp(reset: false)
        XCTAssertTrue(reopened.tabBars.buttons["我的"].exists)
        reopened.tabBars.buttons["我的"].tap()
        reveal(reopened.buttons["profile-language"],in: reopened); reopened.buttons["profile-language"].tap()
        reopened.buttons["language-en"].tap()
        XCTAssertTrue(reopened.tabBars.buttons["Profile"].waitForExistence(timeout: 3))
        reopened.tabBars.buttons["Today"].tap()
        openControls(reopened)
        reopened.buttons["mock-connect"].tap(); reopened.buttons["mock-start-meal"].tap()
        reopened.buttons["mock-short"].tap(); reopened.buttons["mock-replay"].tap()
        totals(reopened,"1 bite · 10 kcal · 0 bites need details")
        reopened.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(reopened.staticTexts["Enjoy your meal"].waitForExistence(timeout: 3))
        shot(reopened,"bilingual-meal-en")
        reopened.terminate()
        let final = openApp(reset: false)
        XCTAssertTrue(final.staticTexts["Every bite counts."].exists)
    }

}
