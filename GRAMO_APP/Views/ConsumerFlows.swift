import SwiftUI
import PhotosUI

struct BindView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: "LET'S CONNECT",title: "让 NOMI 来陪你")
                Image("ProductSpoon").resizable().scaledToFit().frame(height: 220).frame(maxWidth: .infinity)
                Text(store.t(store.deviceReady ? "餐勺已连接，可以开始用餐了。" : "打开餐勺，放在手机附近。\n选择你的餐勺，完成连接。"))
                    .font(.system(size: 15)).foregroundStyle(Palette.secondary).lineSpacing(6)
                if store.isSimulation {
                    #if DEBUG
                    PrimaryButton(title: "连接模拟餐勺",identifier: "mock-connect") { store.mockDevice?.connect() }
                    Text(store.t("当前为隔离模拟模式，无需蓝牙。")).font(.footnote).foregroundStyle(Palette.secondary)
                    #endif
                } else {
                    ForEach(store.nearby.filter { $0.connectable != false }) { device in
                        Button { store.connectNearby(device.id) } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right").frame(width: 32)
                                Text(store.t(store.deviceName(device))).font(.system(size: 16,weight: .medium))
                                Spacer(); Image(systemName: "chevron.right").font(.system(size: 12))
                            }.padding(20).background(.white,in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(ProductPressStyle())
                    }
                    if store.nearby.isEmpty && !store.deviceReady {
                        Text(store.t(status)).font(.system(size: 14)).foregroundStyle(Palette.secondary).accessibilityIdentifier("ble-status")
                    }
                    PrimaryButton(title: store.state.device.phase == .permissionOff ? "允许蓝牙连接" : "重新寻找餐勺",identifier: "ble-rescan") {
                        if store.state.device.phase == .permissionOff { store.openSettings() } else { store.startScan() }
                    }
                }
                if store.deviceReady { PrimaryButton(title: "完成连接",identifier: "connection-done") { dismiss() } }
            }.padding(24)
        }.pageBackground().simulationContext().navigationTitle(store.t("连接餐勺")).onAppear { if !store.isSimulation { store.startScan() } }
    }
    private var status: String {
        switch store.state.device.phase {
        case .permissionOff: return "请允许蓝牙权限，以连接餐勺。"
        case .bluetoothOff: return "请开启手机蓝牙。"
        case .connecting: return "正在连接，请将餐勺保持在附近。"
        case .connectFailed, .syncFailed: return "暂时未能连接，请稍后重试。"
        default: return "尚未发现餐勺。确认设备已开机后，再试一次。"
        }
    }
}
struct DeviceView: View {
    var focus: DeviceFocus = .none
    @Environment(AppStore.self) private var store
    @State private var bind = false
    @State private var camera = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: "YOUR COMPANION",title: "我的 NOMI")
                Image("ProductSpoon").resizable().scaledToFit().frame(height: 255).frame(maxWidth: .infinity)
                Surface {
                    HStack {
                        VStack(alignment: .leading,spacing: 8) {
                            Text(store.t(store.consumerConnection)).font(.system(size: 21,weight: .medium))
                            Text(store.t(store.deviceReady ? "准备好，陪你记录下一餐。" : "连接后，短按餐勺即可留下记录。"))
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Image(systemName: store.deviceReady ? "checkmark.circle" : "link").font(.system(size: 25,weight: .light))
                    }
                }
                if store.deviceReady {
                    PrimaryButton(title: "查看餐勺画面",identifier: "open-spoon-camera") { camera = true }
                    Button(store.t("断开连接")) { store.disconnect() }.font(.system(size: 14)).frame(maxWidth: .infinity).accessibilityIdentifier("device-disconnect")
                } else {
                    PrimaryButton(title: "连接餐勺",identifier: "device-primary") { bind = true }
                }
                Surface {
                    VStack(alignment: .leading,spacing: 20) {
                        instruction("hand.tap", "吃完一口，轻按一下", "开启用餐记录后，离口再短按。信息不全时，稍后补充就好。")
                        Hairline()
                        instruction("power", "长按开关，不会误记", "长按约 1.5 秒并松手进入休眠，再次长按唤醒。")
                        Hairline()
                        instruction("drop", "照顾好你的餐勺", "拆下餐头清洁，保持手柄与充电口干燥。")
                    }
                }
            }.padding(24)
        }.pageBackground()
        .sheet(isPresented: $bind) { NavigationStack { BindView().toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("关闭")) { bind = false } } } } }
        .sheet(isPresented: $camera) { NavigationStack { CameraPreviewView() } }
    }
    private func instruction(_ icon: String,_ title: String,_ detail: String) -> some View {
        HStack(alignment: .top,spacing: 14) {
            Image(systemName: icon).font(.system(size: 19,weight: .light)).frame(width: 25)
            VStack(alignment: .leading,spacing: 7) {
                Text(store.t(title)).font(.system(size: 15,weight: .medium))
                Text(store.t(detail)).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
            }
        }
    }
}
struct CameraPreviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            if let frame = store.spoonFrame, let image = UIImage(data: frame.data) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22))
                Text(store.t(store.cameraStatus.contains("中断") ? "画面已暂停，重新连接后会恢复。" : "餐勺画面 · \(frame.timestamp.formatted(date: .omitted,time: .standard))"))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            } else {
                ProductEmptyState(symbol: "camera",title: store.isSimulation ? "模拟模式没有实拍画面" : "正在等待餐勺画面",message: store.isSimulation ? "可在选菜时使用相册中的照片。" : "连接后请稍等片刻，画面会自动刷新。")
            }
            Spacer()
        }.padding(24).pageBackground().simulationContext().navigationTitle(store.t("餐勺视角")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
        .onAppear { store.setPreview(true, owner: "consumer-camera") }
        .onDisappear { store.setPreview(false, owner: "consumer-camera") }
    }
}
struct MealExperienceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pickDish = false
    @State private var edit: IntakeEvidence?
    @State private var supplement = false
    @State private var device = false
    @State private var mockControls = false
    @State private var ended = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var meal: Meal? { store.state.meals.first { $0.id == store.state.recordingMealId } }
    private var entries: [IntakeEvidence] { (meal?.foods.compactMap(\.evidence) ?? []).sorted { $0.timestamp > $1.timestamp } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: meal == nil ? "A MOMENT FOR YOURSELF" : "ENJOY YOUR MEAL",title: meal == nil ? "这一餐，慢慢吃。" : "专心享受这一餐")
                Surface(dark: true) {
                    VStack(alignment: .leading,spacing: 24) {
                        HStack {
                            HStack(spacing: 7) { Circle().fill(.white).frame(width: 5,height: 5); Text(store.t(meal == nil ? "准备开始" : "正在记录")).font(.system(size: 12)) }
                            Spacer()
                            if let meal {
                                TimelineView(.periodic(from: .now,by: 1)) { c in Text(store.t(ZWFormat.formatTimer(max(0,Int(c.date.timeIntervalSince1970-meal.startedAt/1000))))).font(.system(size: 12)).monospacedDigit() }
                            }
                        }.foregroundStyle(.white.opacity(0.65))
                        HStack(alignment: .firstTextBaseline,spacing: 8) {
                            Text(store.t("\(entries.count)")).font(.system(size: 74,weight: .light)).tracking(-4).monospacedDigit().contentTransition(.numericText()).accessibilityIdentifier("meal-bite-count")
                            Text(store.t("口已记录")).font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
                            Spacer()
                            Image(systemName: "fork.knife").font(.system(size: 35,weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
                        }.foregroundStyle(.white)
                        HStack {
                            Text(store.t(store.state.hideCalories ? "热量已隐藏" : (entries.compactMap(\.estimatedKcal).isEmpty ? "热量待完善" : String(format: "约 %.0f kcal", entries.compactMap(\.estimatedKcal).reduce(0,+))))).font(.system(size: 16,weight: .medium))
                            Spacer()
                            Text(store.t("\(entries.filter { $0.estimatedKcal == nil }.count) 口待完善")).font(.system(size: 12))
                        }.foregroundStyle(.white.opacity(0.7))
                    }
                }
                if meal == nil {
                    PrimaryButton(title: "开始记录本餐",identifier: "begin-recording") { _ = store.ensureIntegrationMeal() }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: store.deviceReady ? "hand.tap" : "link").font(.system(size: 18,weight: .light))
                        Text(store.t(store.consumerButtonStatus)).accessibilityIdentifier("button-recording-status")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        Spacer(minLength: 0)
                        if !store.deviceReady { Button(store.t("连接")) { device = true }.font(.system(size: 13,weight: .medium)) }
                    }
                }
                Button { pickDish = true } label: {
                    Surface {
                        HStack {
                            VStack(alignment: .leading,spacing: 8) {
                                Text(store.t("当前菜品")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                Text(store.currentDish?.displayName(in: store.language) ?? store.t("这餐吃点什么？")).font(.system(size: 20,weight: .medium))
                            }
                            Spacer(); Text(store.t(store.currentDish == nil ? "选菜" : "换一道")).font(.system(size: 13)); Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                    }
                }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("select-current-dish")
                if !store.settings.candidates.isEmpty {
                    ScrollView(.horizontal,showsIndicators: false) {
                        HStack {
                            ForEach(store.settings.candidates) { dish in
                                Button(dish.displayName(in: store.language)) { store.selectDish(dish.id) }
                                    .font(.system(size: 13,weight: .medium)).padding(.horizontal,16).padding(.vertical,10)
                                    .foregroundStyle(store.currentDish?.id == dish.id ? .white : Palette.ink)
                                    .background(store.currentDish?.id == dish.id ? Palette.ink : .white,in: Capsule())
                            }
                        }
                    }
                }
                HStack { Text(store.t("最近一口")).font(.system(size: 20,weight: .semibold)); Spacer(); Button(store.t("补记")) { supplement = true }.font(.system(size: 13)).accessibilityIdentifier("manual-bite") }
                if let entry = entries.first {
                    BiteRow(entry: entry,index: entries.count) { edit = entry }
                } else {
                    Text(store.t("第一口之后，这里会留下时间、菜品和份量。暂时不清楚的部分，可以稍后补充。"))
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(5)
                }
                #if DEBUG
                if store.isSimulation {
                    Button(store.t("模拟餐勺控制")) { mockControls = true }.font(.system(size: 13)).frame(maxWidth: .infinity).padding(14).background(.white,in: Capsule()).accessibilityIdentifier("open-mock-controls")
                }
                #endif
                if let meal {
                    QuietButton(title: "结束本餐",identifier: "end-meal") { store.endMeal(mealId: meal.id); ended = true }
                }
            }.padding(24)
        }.pageBackground().simulationContext().scrollIndicators(.hidden).navigationTitle(store.t("用餐")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("收起")) { dismiss() } } }
        .sheet(isPresented: $pickDish) { NavigationStack { DishPickerView() } }
        .sheet(item: $edit) { entry in NavigationStack { IntakeEditor(existing: entry) } }
        .sheet(isPresented: $supplement) { NavigationStack { IntakeEditor(existing: nil) } }
        .sheet(isPresented: $device) { NavigationStack { BindView() } }
        #if DEBUG
        .sheet(isPresented: $mockControls) { NavigationStack { MockControlsView() }.presentationDetents([.large]) }
        #endif
        .alert(store.t("这一餐已保存"),isPresented: $ended) { Button(store.t("完成")) { dismiss() } } message: { Text(store.t("每一口都已保留。可以在记录里回看和补充。")) }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(store.t(toast)).font(.system(size: 13,weight: .medium)).padding(.horizontal,18).padding(.vertical,12)
                    .foregroundStyle(.white).background(Palette.ink,in: Capsule()).padding(.top,8)
                    .accessibilityIdentifier("meal-toast").allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25),value: entries.count)
    }
}
struct MealLiveView: View { var mealId: String; var body: some View { MealExperienceView() } }
struct BiteRow: View {
    let entry: IntakeEvidence
    var index: Int
    @Environment(AppStore.self) private var store
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Surface {
                HStack(alignment: .top,spacing: 14) {
                    Text(store.t(String(format: "%02d",index))).font(.system(size: 13,weight: .medium)).monospacedDigit().foregroundStyle(Palette.tertiary).padding(.top,3)
                    VStack(alignment: .leading,spacing: 8) {
                        Text(entry.dish?.displayName(in: store.language) ?? store.t("菜品待完善")).font(.system(size: 17,weight: .medium))
                        Text(store.t("\(ZWFormat.formatClock(entry.timestamp)) · \(entry.grams.map { String(format: "约 %.1f g",$0) } ?? "份量待完善")"))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(store.t(store.state.hideCalories ? "—" : entry.estimatedKcal.map { String(format: "%.0f kcal",$0) } ?? "待完善")).font(.system(size: 13,weight: .medium))
                }
            }
        }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("bite-\(entry.eventID)")
    }
}
struct MealDetailView: View {
    var mealId: String
    @Environment(AppStore.self) private var store
    @State private var editing: IntakeEvidence?
    @State private var legacyEntry: LegacyIntake?
    @State private var add = false
    private var meal: Meal? { store.state.meals.first { $0.id == mealId } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                if let meal {
                    ProductHeader(eyebrow: "\(L10n.dateLine(meal.date, week: true, store.language)) · \(meal.time)",title: meal.name)
                    let entries = meal.foods.compactMap(\.evidence)
                    Surface {
                        HStack {
                            Metric(value: "\(entries.count)",unit: "口",title: "进食记录")
                            Metric(value: store.state.hideCalories ? "—" : (entries.isEmpty ? "—" : String(format: "%.0f",entries.compactMap(\.estimatedKcal).reduce(0,+))),unit: "kcal",title: "已计入 · 估算")
                            Metric(value: "\(meal.durationSec/60)",unit: "分钟",title: "用餐时长")
                        }
                    }
                    Text(store.t("每一口，都在这里")).font(.system(size: 20,weight: .semibold))
                    ForEach(Array(entries.enumerated()),id: \.element.key) { index,entry in BiteRow(entry: entry,index: index+1) { editing = entry } }
                    ForEach(meal.foods.filter { $0.evidence == nil }) { food in
                        Button { legacyEntry = LegacyIntake(meal: meal,food: food) } label: {
                            Surface { VStack(alignment: .leading,spacing: 8) { Text(store.t(food.name)).font(.headline); Text(store.t(food.portion)).font(.subheadline).foregroundStyle(Palette.secondary); Text(store.t("历史记录 · 轻点补充份量")).font(.caption).foregroundStyle(Palette.secondary) } }
                        }.buttonStyle(ProductPressStyle())
                    }
                    if meal.foods.isEmpty { ProductEmptyState(symbol: "fork.knife",title: "这一餐还没有口次",message: "开始用餐后，短按餐勺即可记录。") }
                    Text(store.t("轻点任意一口，可补充份量或修正菜品。")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Button(store.t("补记这一餐")) { add = true }.font(.system(size: 14)).frame(maxWidth: .infinity).padding(16)
                }
            }.padding(24)
        }.pageBackground().sheet(item: $editing) { entry in NavigationStack { IntakeEditor(existing: entry) } }
        .sheet(isPresented: $add) { NavigationStack { IntakeEditor(existing: nil, targetMealID: mealId) } }
        .sheet(item: $legacyEntry) { entry in NavigationStack { IntakeEditor(existing: entry.evidence,legacy: entry) } }
    }
}
