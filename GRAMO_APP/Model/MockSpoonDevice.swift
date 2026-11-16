#if DEBUG
import Foundation
import Observation

/// Debug-only adapter. It emits the same validated wire events as NOMI01 and
/// acknowledges them only after AppStore accepts them. Never touches real BLE.
@MainActor @Observable final class MockSpoonDevice: LEDTransport {
    struct Journal: Codable {
        var nonce = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        var sequence: UInt32 = 0
        var pending: [NomiButtonEvent] = []
        var last: NomiButtonEvent?
        var completeEvidence = Set<String>()
        var armedMeal: String?
    }
    private weak var store: AppStore?
    private let defaults: UserDefaults
    private var journal: Journal
    private(set) var poweredOn = true
    private(set) var connected = false
    private(set) var light: GoalColor?
    private(set) var status = "模拟设备待连接"
    var includePortion = true
    var failSync = false
    var queuedCount: Int { journal.pending.count }
    var lastEventID: String? { journal.last?.event }
    private let journalKey = "nomi.mock.journal.v1"
    static let deviceID = "DEB000000001"

    init(store: AppStore, defaults: UserDefaults) {
        self.store = store; self.defaults = defaults
        journal = defaults.data(forKey: journalKey).flatMap { try? JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
    }
    func arm(meal: String?) {
        guard connected, journal.armedMeal != meal else { return }
        journal.armedMeal = meal; persist()
    }
    func connect() {
        guard poweredOn else { status = "模拟设备已关机，请长按开机"; return }
        if failSync {
            connected = false; status = "模拟同步失败 · 队列已保留"
            store?.mockConnection(ready: false, failed: true); return
        }
        connected = true; status = "模拟设备已连接"
        store?.mockConnection(ready: true)
        arm(meal: store?.activeIntegrationMealID)
        deliverPending()
    }
    func disconnect() {
        connected = false; status = "模拟连接已断开"
        store?.mockConnection(ready: false)
    }
    func shortPress() {
        guard poweredOn else { status = "模拟设备已关机，短按无事件"; return }
        guard let meal = journal.armedMeal else { status = "未开始用餐，短按不记口"; return }
        guard journal.pending.count < 64 else { status = "模拟待同步记录已满，请先同步"; return }
        journal.sequence &+= 1
        let event = NomiButtonEvent(v: 1, type: "bite", event: journal.nonce + String(format: "-%08x", journal.sequence),
            device: Self.deviceID, meal: meal, at: Date().timeIntervalSince1970 * 1000)
        journal.last = event; journal.pending.append(event)
        if includePortion { journal.completeEvidence.insert(event.key) }
        persist(); deliverPending()
    }
    func replayLast() {
        guard let last = journal.last, poweredOn else { return }
        if !journal.pending.contains(where: { $0.key == last.key }) { journal.pending.append(last) }
        persist(); deliverPending()
    }
    func longPress() {
        // One completed long gesture changes power only. It never calls shortPress.
        poweredOn.toggle()
        if poweredOn { connect() }
        else { disconnect(); light = nil; status = "模拟设备已关机 · 没有新增口次" }
    }
    private func deliverPending() {
        guard connected, poweredOn, !failSync, let store, store.isSimulation else { return }
        for event in journal.pending {
            let existed = store.state.meals.contains { $0.foods.contains { $0.evidence?.key == event.key } }
            guard store.receiveButton(event) else { continue }
            // A separate synthetic measurement completes the SAME event. A replay
            // must not overwrite a user's correction or resurrect a deleted bite.
            if !existed, journal.completeEvidence.contains(event.key),
               let entry = store.state.meals.flatMap(\.foods).compactMap(\.evidence).first(where: { $0.key == event.key }) {
                var updated = entry
                updated.dish = entry.dish ?? FoodCandidate(id: "mock-dish", name: "米饭", rawLabel: "mock-rice", confidence: nil,
                    source: "Debug 模拟样本", modelVersion: "mock-v1", imageID: nil, region: nil)
                updated.grams = 10; updated.kcalPer100g = 100
                updated.nutritionSource = "Debug 算术样本：100 kcal/100g，非营养参考"
                updated.measurement = "模拟测量 10 g"; updated.note = "隔离演示记录，不能用于真实健康统计。"
                store.saveIntake(updated, mealID: event.meal, correction: true)
            }
            journal.pending.removeAll { $0.key == event.key }; journal.completeEvidence.remove(event.key)
        }
        persist()
        status = queuedCount == 0 ? "模拟记录已同步" : "尚有模拟记录待同步"
    }
    func send(color: GoalColor, commandID: UUID) throws {
        guard connected, poweredOn, !failSync else { throw MockError.disconnected }
        light = color
        Task { @MainActor [weak self] in
            guard let self, self.connected, self.store?.isSimulation == true else { return }
            self.store?.led.acknowledge(commandID, applied: color)
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(journal) { defaults.set(data, forKey: journalKey) }
    }
    enum MockError: Error { case disconnected }
}
#endif
