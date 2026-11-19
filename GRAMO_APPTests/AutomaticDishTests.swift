import XCTest
import UIKit
@testable import GRAMO_APP

final class AutomaticDishTests: XCTestCase {
    private func candidates(_ id: String = "77", score: Double = 0.85) -> [FoodCandidate] {
        [FoodCandidate(id: id, name: id == "77" ? "红烧肉" : "麻婆豆腐", rawLabel: id == "77" ? "Braised pork" : "Mapo Tofu",
            confidence: score, source: "Test classifier output", modelVersion: "test", imageID: nil, classID: id, region: nil),
         FoodCandidate(id: "2", name: "其他候选", rawLabel: "Other", confidence: 0.1, source: "Test", modelVersion: "test", imageID: nil, classID: "2", region: nil)]
    }
    func testConsistencyRequiresTwoDistinctRecentFramesFromSameDeviceAndMeal() {
        let time = Date()
        var frames = [DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(-3), deviceID: "A", mealID: "M", candidates: candidates())]
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time))
        frames.append(DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(-1), deviceID: "A", mealID: "M", candidates: candidates()))
        XCTAssertEqual(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time)?.classID, "77")
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "B", meal: "M", at: time))
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "other", at: time))
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time.addingTimeInterval(13)))
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time.addingTimeInterval(-2)))
        frames[1].frameID = frames[0].frameID
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time))
    }
    func testNewDishAmbiguityAndRecognitionFailureDoNotReuseOldDish() {
        let time = Date()
        var frames = (0..<2).map { DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(Double($0)-4), deviceID: "A", mealID: "M", candidates: candidates()) }
        frames.append(DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(-2), deviceID: "A", mealID: "M", candidates: candidates("0")))
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time))
        frames.append(DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(-1), deviceID: "A", mealID: "M", candidates: candidates("0")))
        XCTAssertEqual(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time)?.classID, "0")
        frames[3].candidates = candidates("0", score: 0.4)
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time))
        frames[3].candidates = []
        XCTAssertNil(AutomaticDish.suggestion(in: frames, device: "A", meal: "M", at: time))
    }
    func testUnclearViewAtPressRetainsRecentPlateButNeverUsesPostPressImage() {
        let time = Date()
        var observations = (0..<2).map { DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(Double($0)-5), deviceID: "A", mealID: "M", candidates: candidates()) }
        observations.append(DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(-1), deviceID: "A", mealID: "M", candidates: []))
        observations.append(DishObservation(frameID: UUID(), timestamp: time.addingTimeInterval(1), deviceID: "A", mealID: "M", candidates: candidates("0")))
        XCTAssertEqual(AutomaticDish.suggestion(in: observations, device: "A", meal: "M", at: time)?.classID, "77")
        XCTAssertNil(AutomaticDish.suggestion(in: observations, device: "A", meal: "M", at: time.addingTimeInterval(15)))
    }
    @MainActor func testInFlightRecognitionCannotCrossSimulationDataBoundary() async {
        let domain = "gramo.auto.\(UUID())", simulatedDomain = "gramo.auto.sim.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!, simulated = UserDefaults(suiteName: simulatedDomain)!
        defer { defaults.removePersistentDomain(forName: domain); simulated.removePersistentDomain(forName: simulatedDomain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal(), time = Date(), predictions = candidates()
        var release: CheckedContinuation<[FoodCandidate], Error>?
        store.recognizeSpoonFrame = { _ in try await withCheckedThrowingContinuation { release = $0 } }
        store.receiveFrame(frame(time))
        while release == nil { await Task.yield() }
        store.receiveButton(event(meal, time.addingTimeInterval(0.1)), now: time.addingTimeInterval(1))
        store.switchSimulation(true, using: simulated)
        release?.resume(returning: predictions)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.isSimulation); XCTAssertEqual(store.todayBiteCount, 0)
        XCTAssertNil(store.automaticDish)
        store.switchSimulation(false)
        XCTAssertEqual(store.todayBiteCount, 1); XCTAssertNil(store.latestIntake?.dish)
    }
    @MainActor private func frame(_ time: Date, device: String = "50F7FAC13DE8") -> SpoonCameraFrame {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { c in
            UIColor.gray.setFill(); c.fill(CGRect(x: 0,y: 0,width: 8,height: 8))
        }
        return SpoonCameraFrame(id: UUID(), data: image.jpegData(compressionQuality: 0.8)!, timestamp: time, deviceID: device)
    }
    @MainActor private func settle(_ store: AppStore) async {
        for _ in 0..<2000 {
            if !store.automaticRecognitionBusy { return }
            await Task.yield()
        }
        XCTFail("Recognition did not settle")
    }
    private func event(_ meal: String, _ time: Date, sequence: Int = 1) -> NomiButtonEvent {
        NomiButtonEvent(v: 1, type: "bite", event: String(format: "0123456789abcdef-%08x", sequence), device: "50F7FAC13DE8", meal: meal, at: time.timeIntervalSince1970*1000)
    }
    @MainActor func testPressSavesImmediatelyThenLateRecognitionEnrichesSameRecordAndSurvivesRelaunch() async throws {
        let domain = "gramo.auto.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal()
        let time = Date(), predictions = candidates()
        store.recognizeSpoonFrame = { _ in predictions }
        XCTAssertTrue(store.receiveFrame(frame(time)))
        await settle(store)
        var release: CheckedContinuation<[FoodCandidate], Error>?
        store.recognizeSpoonFrame = { _ in try await withCheckedThrowingContinuation { release = $0 } }
        XCTAssertTrue(store.receiveFrame(frame(time.addingTimeInterval(0.1))))
        while release == nil { await Task.yield() }
        let press = event(meal, time.addingTimeInterval(0.2))
        XCTAssertTrue(store.receiveButton(press, now: time.addingTimeInterval(0.3)))
        XCTAssertEqual(store.todayBiteCount, 1); XCTAssertNil(store.latestIntake?.dish)
        XCTAssertTrue(store.receiveButton(press, now: time.addingTimeInterval(0.3)))
        release?.resume(returning: predictions)
        await settle(store)
        XCTAssertEqual(store.todayBiteCount, 1)
        XCTAssertEqual(store.latestIntake?.dish?.classID, "77")
        XCTAssertEqual(store.latestIntake?.automaticDish, true)
        XCTAssertNil(store.latestIntake?.grams); XCTAssertNil(store.latestIntake?.estimatedKcal)
        let reopened = AppStore(defaults: defaults)
        XCTAssertEqual(reopened.latestIntake?.dish?.classID, "77")
        XCTAssertEqual(reopened.todayBiteCount, 1)
    }
    @MainActor func testTwoPressesNeedNoPhoneSelectionAndChangingDishUpdatesOnlyNewBites() async {
        let domain = "gramo.auto.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal(), time = Date()
        let pork = candidates(), tofu = candidates("0")
        store.recognizeSpoonFrame = { _ in pork }
        for n in 0..<2 { store.receiveFrame(frame(time.addingTimeInterval(Double(n)*0.1))); await settle(store) }
        XCTAssertEqual(store.todayBiteCount, 0) // images alone never count
        store.receiveButton(event(meal, time.addingTimeInterval(0.3)), now: time.addingTimeInterval(1))
        store.receiveButton(event(meal, time.addingTimeInterval(0.5), sequence: 2), now: time.addingTimeInterval(1))
        XCTAssertEqual(store.todayBiteCount, 2)
        XCTAssertTrue(store.todayIntakes.allSatisfy { $0.dish?.classID == "77" })
        store.recognizeSpoonFrame = { _ in tofu }
        for n in 6..<8 { store.receiveFrame(frame(time.addingTimeInterval(Double(n)*0.1))); await settle(store) }
        store.receiveButton(event(meal, time.addingTimeInterval(0.9), sequence: 3), now: time.addingTimeInterval(1))
        XCTAssertEqual(store.latestIntake?.dish?.classID, "0")
        XCTAssertEqual(store.todayIntakes.filter { $0.dish?.classID == "77" }.count, 2)
        // Evict the earlier plate from the bounded buffer without erasing saved names.
        for n in 10..<24 { store.receiveFrame(frame(time.addingTimeInterval(Double(n)*0.1))); await settle(store) }
        XCTAssertEqual(store.todayIntakes.filter { $0.dish?.classID == "77" }.count, 2)
        XCTAssertEqual(store.latestIntake?.dish?.classID, "0")
    }
    @MainActor func testLateResultCannotOverwriteCorrectionOrRestoreDeletedBite() async {
        let domain = "gramo.auto.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal(), time = Date(), predictions = candidates()
        store.recognizeSpoonFrame = { _ in predictions }
        store.receiveFrame(frame(time)); await settle(store)
        var release: CheckedContinuation<[FoodCandidate], Error>?
        store.recognizeSpoonFrame = { _ in try await withCheckedThrowingContinuation { release = $0 } }
        store.receiveFrame(frame(time.addingTimeInterval(0.1)))
        while release == nil { await Task.yield() }
        let first = event(meal, time.addingTimeInterval(0.2)), second = event(meal, time.addingTimeInterval(0.3), sequence: 2)
        store.receiveButton(first, now: time.addingTimeInterval(1))
        var edit = store.latestIntake!
        edit.dish = candidates("0")[0]; edit.corrected = true
        store.saveIntake(edit, mealID: meal, correction: true)
        store.receiveButton(second, now: time.addingTimeInterval(1)); store.removeIntake(second.key)
        release?.resume(returning: predictions); await settle(store)
        XCTAssertEqual(store.todayBiteCount, 1); XCTAssertEqual(store.latestIntake?.dish?.classID, "0")
    }
    @MainActor func testMissingModelDoesNotBlockPressAndManualLockCanReturnToAutomatic() async {
        let domain = "gramo.auto.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults), meal = store.ensureIntegrationMeal(), time = Date()
        store.recognizeSpoonFrame = { _ in throw RecognitionError.missingModel }
        store.receiveFrame(frame(time)); await settle(store)
        store.receiveButton(event(meal, time.addingTimeInterval(0.1)), now: time.addingTimeInterval(1))
        XCTAssertEqual(store.todayBiteCount, 1); XCTAssertNil(store.latestIntake?.dish)
        XCTAssertTrue(store.automaticRecognitionUnavailable)
        store.confirmCandidate(candidates()[0]); XCTAssertNotNil(store.currentDish)
        store.resumeAutomaticDish(); XCTAssertNil(store.currentDish)
    }
}
