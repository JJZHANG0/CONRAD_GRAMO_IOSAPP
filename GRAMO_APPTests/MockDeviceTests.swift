import XCTest
@testable import GRAMO_APP

@MainActor final class MockDeviceTests: XCTestCase {
    private var domains: [String] = []
    private func sandbox() -> UserDefaults {
        let name = "nomi.tests.\(UUID().uuidString)"; domains.append(name)
        return UserDefaults(suiteName: name)!
    }
    override func tearDown() { for name in domains { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }; domains = [] }
    private func connected(_ defaults: UserDefaults? = nil) -> AppStore {
        let store = AppStore(defaults: defaults ?? sandbox(), simulated: true)
        store.mockDevice!.connect(); _ = store.ensureIntegrationMeal()
        return store
    }
    func testTwoIndependentPressesReplayAndLongPress() {
        let store = connected(), mock = store.mockDevice!
        mock.shortPress(); mock.shortPress(); XCTAssertEqual(store.todayBiteCount,2)
        XCTAssertEqual(store.daily.kcal,20)
        mock.replayLast(); mock.replayLast(); XCTAssertEqual(store.todayBiteCount,2)
        mock.longPress(); XCTAssertFalse(mock.poweredOn); XCTAssertFalse(store.deviceReady)
        mock.shortPress(); XCTAssertEqual(store.todayBiteCount,2)
        mock.longPress(); XCTAssertTrue(store.deviceReady); XCTAssertEqual(store.todayBiteCount,2)
    }
    func testNoMealAndMissingEvidence() {
        let store = AppStore(defaults: sandbox(),simulated: true), mock = store.mockDevice!
        mock.connect(); mock.shortPress(); XCTAssertEqual(store.todayBiteCount,0)
        _ = store.ensureIntegrationMeal(); mock.includePortion = false; mock.shortPress()
        XCTAssertEqual(store.todayBiteCount,1); XCTAssertEqual(store.daily.pending,1)
        XCTAssertNil(store.latestIntake?.grams); XCTAssertNil(store.latestIntake?.estimatedKcal)
    }
    func testOfflineQueueSurvivesProcessRecreationAndSyncFailure() {
        let defaults = sandbox(), store = connected(defaults), mock = store.mockDevice!
        mock.disconnect(); mock.shortPress(); mock.shortPress()
        XCTAssertEqual(store.todayBiteCount,0); XCTAssertEqual(mock.queuedCount,2)
        let reopened = AppStore(defaults: defaults,simulated: true), next = reopened.mockDevice!
        next.failSync = true; next.connect(); XCTAssertEqual(reopened.todayBiteCount,0); XCTAssertEqual(next.queuedCount,2)
        next.failSync = false; next.connect()
        XCTAssertEqual(reopened.todayBiteCount,2); XCTAssertEqual(reopened.daily.kcal,20); XCTAssertEqual(next.queuedCount,0)
        next.connect(); next.replayLast(); XCTAssertEqual(reopened.todayBiteCount,2)
    }
    func testCorrectionThresholdDeletionAndPersistence() async {
        let defaults = sandbox(), store = connected(defaults), mock = store.mockDevice!
        store.setDailyGoal(20); mock.shortPress()
        XCTAssertEqual(mock.light,.green)
        mock.shortPress(); XCTAssertEqual(mock.light,.red)
        var e = store.latestIntake!; e.grams = 2; e.corrected = true; e.dish?.name = "手动改菜"
        store.saveIntake(e,mealID: store.activeIntegrationMealID,correction: true)
        XCTAssertEqual(store.daily.kcal,12); XCTAssertEqual(mock.light,.green)
        mock.replayLast(); XCTAssertEqual(store.daily.kcal,12); XCTAssertEqual(store.latestIntake?.dish?.name,"手动改菜")
        let key = e.key; store.removeIntake(key); mock.replayLast()
        XCTAssertEqual(store.todayBiteCount,1); XCTAssertEqual(store.daily.kcal,10)
        let id = store.activeIntegrationMealID!; store.endMeal(mealId: id)
        let reopened = AppStore(defaults: defaults,simulated: true)
        XCTAssertEqual(reopened.todayBiteCount,1); XCTAssertEqual(reopened.daily.kcal,10)
        XCTAssertNil(reopened.activeIntegrationMealID)
        await Task.yield()
    }
    func testSimulationUsesSeparateStorageAndKeepsSource() {
        let production = UserDefaults.standard.data(forKey: "zhiweishao.store.v1")
        let store = connected(); store.mockDevice!.shortPress()
        XCTAssertEqual(UserDefaults.standard.data(forKey: "zhiweishao.store.v1"), production)
        XCTAssertTrue(store.isSimulation)
        XCTAssertEqual(store.latestIntake?.deviceID,MockSpoonDevice.deviceID)
        XCTAssertTrue(store.latestIntake?.nutritionSource.contains("Debug") == true)
        XCTAssertTrue(store.dataDirectory.path.hasSuffix("Simulation"))
    }
    func testSwitchingModesRestoresBothIndependentLedgers() {
        let real = sandbox(), simulated = sandbox()
        let store = AppStore(defaults: real)
        store.setDailyGoal(1800)
        let realSnapshot = real.data(forKey: "zhiweishao.store.v1")
        store.switchSimulation(true, using: simulated)
        store.mockDevice!.connect(); _ = store.ensureIntegrationMeal(); store.mockDevice!.shortPress()
        store.setDailyGoal(20)
        XCTAssertEqual(store.todayBiteCount,1)
        XCTAssertEqual(real.data(forKey: "zhiweishao.store.v1"),realSnapshot)
        store.switchSimulation(false)
        XCTAssertFalse(store.isSimulation); XCTAssertNil(store.mockDevice)
        XCTAssertEqual(store.todayBiteCount,0); XCTAssertEqual(store.settings.dailyGoal,1800)
        store.switchSimulation(true, using: simulated)
        XCTAssertEqual(store.todayBiteCount,1); XCTAssertEqual(store.settings.dailyGoal,20)
        XCTAssertFalse(store.deviceReady) // restored records do not forge a live connection
    }
}
