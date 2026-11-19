import Foundation
import Observation
import UIKit

struct SyncOutcome: Equatable {
    var ok: Bool
    var message: String
    var added: Int
}

@MainActor
@Observable
final class AppStore {
    private(set) var state = Logic.createInitial(Date())
    var bag: [BagLine] = []
    var toast: String?
    var nearby: [NearbyDevice] = []
    let radio = SpoonRadio()
    var gattDiagnostics = "尚未发现 GATT" { didSet { saveRadioDiagnostics() } }
    var deviceInformation: [String: String] = [:] { didSet { saveRadioDiagnostics() } }
    var deviceReady = false
    var daily = DailyIntake()
    var todayISO = ZWFormat.formatISODate(Date())
    var nomiCapabilities: NomiInfo?
    var spoonFrame: SpoonCameraFrame?
    var cameraBusy = false
    var cameraMessage = "勺载相机尚未就绪"
    var cameraStatus = "尚未收到勺载画面"
    var buttonSessionReady = false
    var buttonMessage = "实体按钮尚未就绪"
    var appActive = true
    var previewOwners = Set<String>()
    private var recentFrames: [SpoonCameraFrame] = []
    var activeIntegrationMealID: String? {
        state.meals.first { $0.id == state.recordingMealId && $0.status == .recording }?.id
    }
    func setPreview(_ enabled: Bool, owner: String) {
        if enabled { previewOwners.insert(owner) } else { previewOwners.remove(owner) }
    }
    var ledSummary: String {
        switch led.status {
        case .unsupported: return "实体 LED：设备不支持或协议尚未核实"
        case .unset: return "实体 LED：未设置每日目标"
        case .disconnected: return "实体 LED：设备未就绪，尚未同步"
        case .pending: return "实体 LED：已发送，等待设备应用回执"
        case .failed: return "实体 LED：未收到应用确认，请重新同步"
        case .applied(let color): return "实体 LED：\(color == .red ? "红色" : "绿色")输出已回执；实际亮灯待目视确认"
        }
    }
    var led = LEDSync()
    private var pendingPackets: [(SpoonPacket, Date)] = []
    var settings: IntegrationSettings { state.integration ?? IntegrationSettings() }
    var currentDish: FoodCandidate? { settings.candidates.first { $0.id == settings.currentDishID } }
    var dailySummary: String {
        if state.hideCalories { return "热量已隐藏，另有 \(daily.pending) 口/项待确认" }
        return String(format: "已计入约 %.1f kcal，另有 %d 口/项待确认", daily.kcal, daily.pending)
    }
    var latestIntake: IntakeEvidence? { state.meals.flatMap(\.foods).compactMap(\.evidence).max { $0.timestamp < $1.timestamp } }


    private var syncLock = false
    private var finishTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    @ObservationIgnored private var defaults: UserDefaults = .standard
    @ObservationIgnored private var productionDefaults: UserDefaults = .standard
    @ObservationIgnored private var simulationDomain = AppStore.simulationSuite
    private(set) var isSimulation = false
    var developerMode = false
    #if DEBUG
    var mockDevice: MockSpoonDevice?
    #endif
    static let simulationSuite = "com.kanglaide.zhiweishao.simulation.v1"
    var dataDirectory: URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return isSimulation ? root.appendingPathComponent("Simulation", isDirectory: true) : root
    }
    var todayIntakes: [IntakeEvidence] { intakes(on: todayISO) }
    func intakes(on day: String) -> [IntakeEvidence] {
        var seen = Set<String>()
        return state.meals.flatMap(\.foods).compactMap(\.evidence)
            .filter { ZWFormat.formatISODate($0.timestamp) == day && seen.insert($0.key).inserted }
            .sorted { $0.timestamp > $1.timestamp }
    }
    var todayBiteCount: Int { todayIntakes.count }
    var consumerConnection: String {
        if deviceReady { return "已连接" }
        switch state.device.phase {
        case .connecting, .syncing: return "正在连接"
        case .permissionOff: return "需要蓝牙权限"
        case .bluetoothOff: return "蓝牙未开启"
        default: return "未连接"
        }
    }
    var consumerButtonStatus: String {
        guard activeIntegrationMealID != nil else { return "开始本餐后即可短按记录" }
        guard deviceReady else { return "餐勺未连接。已保存的记录不会丢失。" }
        if isSimulation || buttonSessionReady { return "吃完离口后，短按餐勺记录这一口。" }
        if nomiCapabilities?.button != true { return "此设备尚未支持按键记录，可先手动补记。" }
        return "正在准备按键记录，请稍候…"
    }
    func synchronizeSession() {
        #if DEBUG
        if isSimulation { mockDevice?.arm(meal: activeIntegrationMealID); return }
        #endif
        radio.syncSession(meal: activeIntegrationMealID, force: true)
    }

    private static let storageKey = "zhiweishao.store.v1"
    private static let bagKey = "zhiweishao.bag.v1"
    private static let languageKey = "zhiweishao.language.v1"
    private static let languagePreferenceKey = "zhiweishao.language.preference.v2"
    var language: AppLanguage = .en

    init(defaults injectedDefaults: UserDefaults? = nil, simulated: Bool = false) {
        let arguments = ProcessInfo.processInfo.arguments
        if let injectedDefaults { defaults = injectedDefaults; productionDefaults = injectedDefaults }
        #if DEBUG
        if arguments.contains("-ui-testing") && injectedDefaults == nil {
            productionDefaults = UserDefaults(suiteName: "com.kanglaide.zhiweishao.uitests.production")!
            defaults = productionDefaults
            simulationDomain += ".uitests"
            if arguments.contains("-reset-ui-testing") { defaults.removePersistentDomain(forName: "com.kanglaide.zhiweishao.uitests.production") }
        }
        if simulated || (injectedDefaults == nil && (arguments.contains("-mock-device") || arguments.contains("-demo-data"))) {
            if injectedDefaults == nil { defaults = UserDefaults(suiteName: simulationDomain)! }
            isSimulation = true
        }
        developerMode = arguments.contains("-developer-mode") || isSimulation
        if isSimulation && arguments.contains("-reset-simulation") {
            defaults.removePersistentDomain(forName: simulationDomain)
        }
        if arguments.contains("-reset-store") {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.bagKey)
            defaults.removeObject(forKey: Self.languageKey)
        }
        #endif
        if let saved = Self.load(defaults), saved.version == 1 {
            if defaults.data(forKey: Self.storageKey + ".pre-integration-backup") == nil,
               let original = defaults.data(forKey: Self.storageKey) {
                defaults.set(original, forKey: Self.storageKey + ".pre-integration-backup")
            }
            var next = saved
            let now = ZWFormat.nowMS()
            for meal in next.meals where meal.status == .settling {
                next = Logic.applyFinishMeal(next, mealId: meal.id, now: now)
            }
            state = Logic.dropLiveLink(next)
        } else {
            state = Logic.createInitial(Date())
        }
        bag = Self.loadBag(defaults)
        if let index = arguments.firstIndex(of: "-language"), arguments.indices.contains(index + 1),
           let forced = AppLanguage(rawValue: arguments[index + 1]) {
            language = forced
        } else {
            language = AppLanguage(rawValue: productionDefaults.string(forKey: Self.languagePreferenceKey) ?? "") ?? .en
        }
        defaults.set(language.rawValue, forKey: Self.languageKey)
        #if DEBUG
        if arguments.contains("-demo-data") && arguments.contains("-reset-store") {
            state.meals = MockData.buildMeals(today: state.seedDate)
        }
        #endif
        radio.attach(self)
        #if DEBUG
        if isSimulation { mockDevice = MockSpoonDevice(store: self, defaults: defaults) }
        #endif
        persist()
    }

    func t(_ source: String) -> String {
        L10n.text(source, language)
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        productionDefaults.set(language.rawValue, forKey: Self.languagePreferenceKey)
        defaults.set(language.rawValue, forKey: Self.languageKey)
    }

    func setHideCalories(_ on: Bool) {
        state.hideCalories = on
        persist()
    }

    func setTrainingConsent(_ on: Bool) {
        state.trainingConsent = on
        persist()
    }

    func saveProfile(heightCm: String, weightKg: String, goal: String) {
        state.profile.heightCm = heightCm.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile.weightKg = weightKg.trimmingCharacters(in: .whitespacesAndNewlines)
        state.profile.goal = goal
        persist()
    }

    func startScan() {
        guard !isSimulation else { return }
        radio.start()
    }

    func connectNearby(_ id: UUID) {
        guard !isSimulation else { return }
        radio.connect(id: id)
    }

    func deviceName(_ device: NearbyDevice) -> String {
        settings.deviceAliases?[device.id.uuidString] ?? device.name
    }

    func setDeviceAlias(_ id: UUID, name: String) {
        var value = settings
        var aliases = value.deviceAliases ?? [:]
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        aliases[id.uuidString] = trimmed.isEmpty ? nil : trimmed
        value.deviceAliases = aliases; state.integration = value; persist()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func radioScanStarted() {
        nearby = []
        deviceReady = false; deviceInformation = [:]; gattDiagnostics = "尚未选择设备；下面仅为本轮广播"
        state = Logic.applyScanning(state)
        persist()
    }

    func radioDiscovered(id: UUID, name: String, rssi: Int, services: [String] = [], manufacturer: String = "", connectable: Bool? = nil) {
        let shown = name.isEmpty ? "未命名" : name
        if let index = nearby.firstIndex(where: { $0.id == id }) {
            nearby[index].name = shown
            nearby[index].rssi = rssi
            nearby[index].advertisedServices = services
            nearby[index].manufacturerHex = manufacturer
            nearby[index].connectable = connectable
        } else {
            nearby.append(NearbyDevice(id: id, name: shown, rssi: rssi, advertisedServices: services, manufacturerHex: manufacturer, connectable: connectable))
        }
        nearby.sort {
            let a = $0.advertisedServices.contains(SpoonLink.service.uuidString)
            let b = $1.advertisedServices.contains(SpoonLink.service.uuidString)
            if a != b { return a }
            return $0.rssi > $1.rssi
        }
        saveRadioDiagnostics()
    }

    func radioConnecting(name: String) {
        deviceReady = false; pendingPackets = []; deviceInformation = [:]; gattDiagnostics = "正在发现 GATT"
        state = Logic.applyConnecting(state, name: name)
        persist()
    }

    func radioConnectFailed(name: String) {
        state = Logic.applyConnectFailed(state, name: name)
        persist()
    }

    func radioDisconnected() {
        pendingPackets = []; deviceReady = false
        state = Logic.applyDisconnect(state)
        persist()
    }

    func radioPermissionDenied() {
        nearby = []
        state = Logic.applyDenyBluetooth(state)
        persist()
    }

    func radioPoweredOff() {
        nearby = []
        state = Logic.applyBluetoothOff(state)
        persist()
    }

    func radioUnavailable() {
        nearby = []
        state = Logic.applyRadioUnavailable(state)
        persist()
    }

    func radioForeignDevice(name: String) {
        let before = state.meals
        state = Logic.applyForeignLink(state, name: name)
        state.meals = before
        persist()
    }

    func radioFoundSpoonService(name: String) {
        state = Logic.applySpoonService(state, name: name)
        persist()
    }

    func radioPacket(_ packet: SpoonPacket) {
        applyRadioPacket(packet)
        persist()
    }

    func calibrate() {
        flash("没有原始载荷协议和砝码验证，不能宣称校准完成。")
    }

    func disconnect() {
        #if DEBUG
        if isSimulation { mockDevice?.disconnect(); return }
        #endif
        radio.disconnect()
        state = Logic.applyDisconnect(state)
        persist()
    }

    func setHead(_ head: UtensilHead) {
        guard state.device.spoonLinked else { return }
        state = Logic.applyHead(state, head: head)
        persist()
    }

    func sync() async -> SyncOutcome {
        if syncLock { return SyncOutcome(ok: false, message: "请稍等，正在处理。", added: 0) }
        syncLock = true
        defer { syncLock = false }
        return await runSync()
    }

    private func runSync() async -> SyncOutcome {
        #if DEBUG
        if isSimulation {
            let before = todayBiteCount
            mockDevice?.connect()
            return SyncOutcome(ok: deviceReady, message: deviceReady ? "记录已同步" : "同步未完成，请重试", added: todayBiteCount-before)
        }
        #endif
        let phase = state.device.phase
        if phase == .disconnected {
            return SyncOutcome(ok: false, message: "连接已断开，请先重新连接。", added: 0)
        }
        if phase == .unbound || phase == .permissionOff || phase == .bluetoothOff || phase == .unavailable || phase == .connectFailed || phase == .scanning {
            return SyncOutcome(ok: false, message: "请先连接餐具。", added: 0)
        }
        if !state.device.speaksSpoon {
            return SyncOutcome(ok: false, message: "这还不是智慧勺，不会新增餐次。", added: 0)
        }
        if phase == .connecting || phase == .syncing {
            return SyncOutcome(ok: false, message: "请稍等，正在处理。", added: 0)
        }
        guard radio.writeSync() else {
            return SyncOutcome(ok: false, message: "没有已验证的数据或可写同步特征，未发送命令。", added: 0)
        }
        radioNote("已发送同步请求，等待数据。")
        return SyncOutcome(ok: true, message: "已发送，等待设备回应", added: 0)
    }

    func showSyncFailure() async {
        flash("Debug 提示示例：同步超时。此按钮未改变真实设备状态。")
    }

    func startMeal() -> MealStart {
        if let step = Logic.mealStartStep(state) {
            return .blocked(step)
        }
        let started = Logic.applyStartMeal(state, now: ZWFormat.nowMS())
        state = started.state
        persist()
        return .started(started.meal.id)
    }

    func endMeal(mealId: String) {
        let now = ZWFormat.nowMS()
        state = Logic.applyEndMeal(state, mealId: mealId, now: now)
        persist()
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            guard Logic.findMeal(self.state, mealId: mealId)?.status == .settling else { return }
            self.state = Logic.applyFinishMeal(self.state, mealId: mealId, now: ZWFormat.nowMS())
            self.persist()
        }
    }

    func saveCorrection(mealId: String, foodId: String, optionId: String) {
        state = Logic.applyCorrection(state, mealId: mealId, foodId: foodId, optionId: optionId, now: ZWFormat.nowMS())
        persist()
        flash("已更新本餐")
    }

    func addFood(_ input: AddFoodInput) -> (mealId: String, pending: Bool) {
        let result = Logic.applyAddEntry(state, input: input, now: ZWFormat.nowMS())
        state = result.state
        persist()
        flash(result.pending ? "已记下，待估算" : "已加入记录")
        return (result.mealId, result.pending)
    }

    func deleteLocalMeals() {
        state = Logic.clearMeals(state)
        var value = settings; value.candidates = []; value.currentDishID = nil; value.mealID = nil; state.integration = value
        defaults.removeObject(forKey: Self.storageKey + ".pre-integration-backup")
        let frames = dataDirectory.appendingPathComponent("Keyframes")
        try? FileManager.default.removeItem(at: frames)
        persist()
        flash("记录已删除")
    }

    func resetRecords() {
        finishTask?.cancel()
        state = Logic.createInitial(Date())
        persist()
    }

    func addToBag(productId: String) {
        if let index = bag.firstIndex(where: { $0.productId == productId }) {
            bag[index].quantity += 1
        } else {
            bag.append(BagLine(productId: productId, quantity: 1))
        }
        persistBag()
        flash("已放入购物袋")
    }

    func bagCount() -> Int {
        bag.reduce(0) { $0 + $1.quantity }
    }

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard let self, !Task.isCancelled, self.toast == text else { return }
            self.toast = nil
        }
    }

    func refreshDay(now: Date = Date()) {
        let date = ZWFormat.formatISODate(now)
        if todayISO != date { todayISO = date }
        daily = IntakeLedger.day(state.meals, now: now)
        var transport: LEDTransport? = radio.canControlLED ? radio : nil
        #if DEBUG
        if isSimulation { transport = mockDevice }
        #endif
        led.update(color: daily.color(goal: settings.dailyGoal), connected: deviceReady, transport: transport, now: now)
        if let frame = spoonFrame {
            cameraStatus = radio.canCapture && now.timeIntervalSince(frame.timestamp) <= 6 ? "相机画面可用 · 间隔刷新 · \(frame.timestamp.formatted(date: .omitted, time: .standard))" : "画面已中断 / 停更 · 最近 \(frame.timestamp.formatted(date: .omitted, time: .standard))"
        } else { cameraStatus = radio.canCapture ? "相机已连接，等待第一帧" : "尚未收到勺载画面" }
        if !isSimulation { radio.tick(now: now, preview: appActive && (!previewOwners.isEmpty || activeIntegrationMealID != nil)) }
    }
    func nomiReady(name: String) {
        state.device.peripheralName = name
        state.device.speaksSpoon = true; state.device.spoonLinked = true
        state.device.phase = .connected; state.device.note = "NOMI01 握手成功；相机和 LED 独立检测。重量、IMU、接触传感器未接入。"
        radioReadiness(true); persist()
    }
    func resyncLED() { led.resync(); refreshDay(); synchronizeSession() }
    @discardableResult func receiveFrame(_ frame: SpoonCameraFrame) -> Bool {
        guard let decoded = UIImage(data: frame.data), decoded.size.width > 0 else { return false }
        spoonFrame = frame
        recentFrames.append(frame)
        recentFrames = Array(recentFrames.filter { frame.timestamp.timeIntervalSince($0.timestamp) <= 20 }.suffix(12))
        var changed = false
        // Add the first post-confirmation frame to the same record, without replacing corrections.
        for mi in state.meals.indices {
            for fi in state.meals[mi].foods.indices {
                guard var e = state.meals[mi].foods[fi].evidence, e.deviceID == frame.deviceID,
                      e.eventID.range(of: "^[0-9a-f]{16}-[0-9a-f]{8}$", options: .regularExpression) != nil,
                      frame.timestamp > e.timestamp, frame.timestamp.timeIntervalSince(e.timestamp) <= 6,
                      !(e.frames ?? []).contains(where: { $0.phase == "after" }) else { continue }
                if let reference = retainFrame(frame, phase: "after") {
                    e.frames = (e.frames ?? []) + [reference]; state.meals[mi].foods[fi].evidence = e; changed = true
                }
            }
        }
        if changed { persist() }; return true
    }
    private func retainFrame(_ frame: SpoonCameraFrame, phase: String) -> IntakeFrame? {
        let relative = "BiteFrames/\(frame.id.uuidString).jpg"
        let root = dataDirectory
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("BiteFrames"), withIntermediateDirectories: true)
            try frame.data.write(to: root.appendingPathComponent(relative), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return IntakeFrame(id: frame.id.uuidString, timestamp: frame.timestamp, relativePath: relative, phase: phase)
        } catch { return nil }
    }
    @discardableResult func receiveButton(_ event: NomiButtonEvent, now: Date = Date()) -> Bool {
        guard event.valid else { return false }
        if settings.deletedEventKeys.contains(event.key) || state.meals.contains(where: { $0.foods.contains { $0.evidence?.key == event.key } }) { return true }
        guard let meal = state.meals.first(where: { $0.id == event.meal }), event.belongs(to: meal, now: now) else {
            buttonMessage = "已忽略非用餐时段短按；未增加记录"; return true
        }
        let selected = settings.currentDishSince.map { event.timestamp >= $0 } == true && event.meal == activeIntegrationMealID ? currentDish : nil
        let nearbyFrames = recentFrames.filter { $0.deviceID == event.device && $0.timestamp <= event.timestamp && event.timestamp.timeIntervalSince($0.timestamp) <= 12 }
            .suffix(4)
        let evidence = IntakeEvidence(eventID: event.event, deviceID: event.device, timestamp: event.timestamp,
            dish: selected, grams: nil, kcalPer100g: nil, nutritionSource: "", measurement: "实体短按确认，份量待补录",
            confirmedEating: true, corrected: false, note: "吃完离口后短按；附近关键帧仅供核对，不能单独证明食物或克数。", frames: [])
        saveIntake(evidence, mealID: event.meal)
        buttonMessage = "已记录一口 · 菜名或份量缺失时待确认"; flash("已记录 · 第 \(todayBiteCount) 口")
        Task { [weak self] in
            guard let self else { return }
            let frames = nearbyFrames.compactMap { self.retainFrame($0, phase: "before") }
            // Merge with the current record: never resurrect a deleted bite or undo a correction.
            if !frames.isEmpty, let mi = self.state.meals.firstIndex(where: { $0.id == event.meal }),
               let fi = self.state.meals[mi].foods.firstIndex(where: { $0.evidence?.key == event.key }),
               var current = self.state.meals[mi].foods[fi].evidence {
                current.frames = (current.frames ?? []) + frames
                self.state.meals[mi].foods[fi].evidence = current; self.persist()
            }
            self.recordHardwareEvidence()
        }
        return true
    }
    func recordHardwareEvidence() {
        #if DEBUG
        let root = dataDirectory
        let object: [String: Any] = ["timestamp": Date().ISO8601Format(), "ready": deviceReady,
            "firmware": nomiCapabilities?.fw ?? "unknown", "led": ledSummary,
            "camera": cameraMessage, "imageBytes": spoonFrame?.data.count ?? 0,
            "imageCRC32": spoonFrame.map { String(NomiWire.crc32($0.data), radix: 16) } ?? "",
            "dailyKcal": daily.kcal, "pending": daily.pending, "goal": settings.dailyGoal as Any? ?? NSNull(),
            "button": buttonMessage, "eventKeys": state.meals.flatMap(\.foods).compactMap { $0.evidence?.key }]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("HardwareEvidence.json"), options: .atomic)
        }
        if let frame = spoonFrame { try? frame.data.write(to: root.appendingPathComponent("LastSpoonFrame.jpg"), options: .atomic) }
        #endif
    }
    func radioReadiness(_ ready: Bool) {
        deviceReady = ready
        if ready { state.device.phase = .connected }
        refreshDay(); saveRadioDiagnostics()
    }
    private func saveRadioDiagnostics() {
        #if DEBUG
        let object: [String: Any] = ["capturedAt": Date().ISO8601Format(), "ready": deviceReady,
                                  "gatt": gattDiagnostics, "deviceInformation": deviceInformation,
                                  "nearby": nearby.map { ["id": $0.id.uuidString, "name": $0.name, "rssi": String($0.rssi), "services": $0.advertisedServices.joined(separator: ","), "manufacturerHex": $0.manufacturerHex, "connectable": $0.connectable.map(String.init) ?? "unknown"] }]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            let url = dataDirectory.appendingPathComponent("BLEInventory.json")
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }
    func radioNote(_ note: String, failure: Bool = false) {
        state.device.note = note
        if failure { state.device.phase = .syncFailed }
        persist()
    }
    func setDailyGoal(_ goal: Double?) {
        var value = settings
        value.dailyGoal = goal.flatMap { $0.isFinite && $0 > 0 && $0 <= 100_000 ? $0 : nil }
        state.integration = value; persist()
    }
    @discardableResult func ensureIntegrationMeal() -> String {
        if let id = settings.mealID, state.meals.contains(where: { $0.id == id && $0.status == .recording }) { return id }
        if !state.recordingMealId.isEmpty, state.meals.contains(where: { $0.id == state.recordingMealId && $0.status == .recording }) {
            var value = settings; value.mealID = state.recordingMealId; state.integration = value; persist()
            return state.recordingMealId
        }
        let result = Logic.applyStartMeal(state, now: ZWFormat.nowMS())
        state = result.state
        var value = settings; value.mealID = result.meal.id; value.candidates = []; value.currentDishID = nil
        state.integration = value; persist(); return result.meal.id
    }
    func confirmCandidate(_ candidate: FoodCandidate) {
        _ = ensureIntegrationMeal()
        var value = settings
        // Same class can occur in multiple regions; preserve a separate candidate identity.
        var chosen = candidate
        chosen.id = UUID().uuidString
        value.candidates.append(chosen); value.currentDishID = chosen.id; value.currentDishSince = Date()
        state.integration = value; persist()
    }
    func selectDish(_ id: String) {
        var value = settings; value.currentDishID = id; value.currentDishSince = Date(); state.integration = value; persist()
    }
    func saveIntake(_ evidence: IntakeEvidence, mealID: String? = nil, correction: Bool = false) {
        let id = mealID ?? ensureIntegrationMeal()
        state = IntakeLedger.upsert(evidence, mealID: id, in: state, correction: correction)
        persist()
    }
    func reconcileLegacy(mealID: String, foodID: String, evidence: IntakeEvidence) {
        guard let mi = state.meals.firstIndex(where: { $0.id == mealID }),
              let fi = state.meals[mi].foods.firstIndex(where: { $0.id == foodID && $0.evidence == nil }) else { return }
        state.meals[mi].foods[fi] = evidence.food
        state.meals[mi].briefCount = -1
        state.meals[mi].updatedAt = ZWFormat.nowMS()
        persist()
    }
    func removeIntake(_ key: String) {
        var value = settings; value.deletedEventKeys.append(key); state.integration = value
        for i in state.meals.indices { state.meals[i].foods.removeAll { $0.evidence?.key == key }; state.meals[i].briefCount = -1 }
        persist()
    }
    private func applyRadioPacket(_ packet: SpoonPacket) {
        let deviceID = radio.deviceID
        let now = Date()
        pendingPackets.removeAll { now.timeIntervalSince($0.1) > 10 }
        let mealNumber: UInt32?
        switch packet {
        case .sample(let id, _, _, _), .mealEnd(let id, _, _): mealNumber = id
        default: mealNumber = nil
        }
        if let mealNumber, !state.meals.contains(where: { $0.id == "spoon-\(deviceID)-\(mealNumber)" }) {
            if pendingPackets.count < 100 { pendingPackets.append((packet, now)) }
            return
        }
        state = Logic.applySpoonPacket(state, packet, now: ZWFormat.nowMS(), deviceID: deviceID)
        switch packet {
        case .sample: break // sensor flags never replace a physical short press
        case .mealStart:
            let queued = pendingPackets; pendingPackets = []
            for (packet, _) in queued { applyRadioPacket(packet) }
        default: break
        }
    }

    private func patchDevice(_ body: (inout DeviceState) -> Void) {
        body(&state.device)
        persist()
    }

    private func persist() {
        refreshDay()
        #if DEBUG
        if isSimulation { mockDevice?.arm(meal: activeIntegrationMealID) }
        else { radio.syncSession(meal: activeIntegrationMealID) }
        #else
        radio.syncSession(meal: activeIntegrationMealID)
        #endif
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-reset-store") || ProcessInfo.processInfo.arguments.contains("-mock-device") else { return }
        #endif
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func persistBag() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-reset-store") || ProcessInfo.processInfo.arguments.contains("-mock-device") else { return }
        #endif
        if let data = try? JSONEncoder().encode(bag) {
            defaults.set(data, forKey: Self.bagKey)
        }
    }


    #if DEBUG
    func switchSimulation(_ enabled: Bool, using simulationDefaults: UserDefaults? = nil) {
        guard enabled != isSimulation else { return }
        finishTask?.cancel(); radio.disconnect(); mockDevice = nil
        isSimulation = enabled
        defaults = enabled ? (simulationDefaults ?? UserDefaults(suiteName: simulationDomain)!) : productionDefaults
        state = Logic.dropLiveLink(Self.load(defaults) ?? Logic.createInitial(Date()))
        bag = Self.loadBag(defaults)
        nearby = []; deviceReady = false; nomiCapabilities = nil; spoonFrame = nil; recentFrames = []
        previewOwners = []; led = LEDSync(); toast = nil
        if enabled { mockDevice = MockSpoonDevice(store: self, defaults: defaults) }
        persist()
    }
    func resetSimulation() {
        guard isSimulation else { return }
        finishTask?.cancel()
        defaults.removePersistentDomain(forName: simulationDomain)
        state = Logic.createInitial(Date()); bag = []; deviceReady = false; led = LEDSync()
        mockDevice = MockSpoonDevice(store: self, defaults: defaults)
        persist()
    }
    func mockConnection(ready: Bool, failed: Bool = false) {
        guard isSimulation else { return }
        deviceReady = ready
        state.device.phase = ready ? .connected : (failed ? .syncFailed : .disconnected)
        state.device.peripheralName = "NOMI · 模拟餐勺"
        state.device.spoonLinked = ready; state.device.speaksSpoon = ready
        state.device.head = .spoon; state.device.battery = nil
        buttonMessage = ready ? "模拟按钮已连接" : "模拟设备未连接"
        persist()
    }
    #endif

    private static func load(_ defaults: UserDefaults) -> AppState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    private static func loadBag(_ defaults: UserDefaults) -> [BagLine] {
        guard let data = defaults.data(forKey: bagKey),
              let lines = try? JSONDecoder().decode([BagLine].self, from: data) else { return [] }
        return lines
    }
}
