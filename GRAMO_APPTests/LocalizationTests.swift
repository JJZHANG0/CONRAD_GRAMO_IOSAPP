import XCTest
@testable import GRAMO_APP

final class LocalizationTests: XCTestCase {
    @MainActor
    func testEnglishDefaultAndExplicitChoiceSurviveRelaunchWithoutChangingRecords() throws {
        let domain = "nomi.language.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        // The previous version wrote its Chinese default even without a user choice.
        defaults.set("zh", forKey: "zhiweishao.language.v1")
        let store = AppStore(defaults: defaults)
        XCTAssertEqual(store.language, .en)
        store.setDailyGoal(1800)
        let records = defaults.data(forKey: "zhiweishao.store.v1")
        store.setLanguage(.zh)
        XCTAssertEqual(defaults.data(forKey: "zhiweishao.store.v1"), records)
        let reopened = AppStore(defaults: defaults)
        XCTAssertEqual(reopened.language, .zh)
        XCTAssertEqual(reopened.settings.dailyGoal, 1800)
        reopened.setLanguage(.en)
        XCTAssertEqual(AppStore(defaults: defaults).language, .en)
    }
    func testDynamicConsumerCopyAndUserNames() {
        XCTAssertEqual(L10n.text("已记录 · 第 8 口", .en), "Recorded · Bite 8")
        XCTAssertEqual(L10n.text("8 口 · 20 kcal · 1 口待完善", .en), "8 bites · 20 kcal · 1 bite needs details")
        XCTAssertEqual(L10n.text("每日目标  1800 kcal", .en), "Daily goal  1800 kcal")
        XCTAssertEqual(L10n.text("12:30 · 约 10.0 g", .en), "12:30 · About 10.0 g")
        XCTAssertEqual(L10n.text("妈妈的私房菜", .en), "妈妈的私房菜")
        XCTAssertEqual(L10n.text("已记录 · 第 8 口", .zh), "已记录 · 第 8 口")
        XCTAssertEqual(L10n.text("YOUR TABLE", .zh), "你的餐桌")
        var dish = FoodCandidate(id: "sample", name: "自选菜", rawLabel: "Model dish", confidence: 0.8,
                                 source: "Core ML", modelVersion: "test", imageID: nil, classID: "1", region: nil)
        XCTAssertEqual(dish.displayName(in: .en), "Model dish")
        XCTAssertEqual(dish.displayName(in: .zh), "自选菜")
        dish.modelVersion = "manual-v1"; dish.name = "妈妈的私房菜"
        XCTAssertEqual(dish.displayName(in: .en), "妈妈的私房菜")
    }
}
