#if DEBUG
import SwiftUI

struct DeveloperToolsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var integration = false
    var body: some View {
        Form {
            Section(store.t("独立开发环境")) {
                Text(store.t("Debug 专用。模拟数据使用独立存储，不会合并进真实记录。关闭模拟模式即可回到原数据。"))
                Toggle(store.t("模拟设备模式"),isOn: Binding(get: { store.isSimulation },set: { store.switchSimulation($0) })).accessibilityIdentifier("mock-mode")
                if store.isSimulation { NavigationLink(store.t("打开模拟餐勺控制")) { MockControlsView() }.accessibilityIdentifier("debug-mock-controls") }
            }
            Section(store.t("真实通道诊断")) {
                Button(store.t("相机、模型与硬件联调")) { integration = true }.disabled(store.isSimulation)
                DisclosureGroup(store.t("连接日志与设备信息")) {
                    Text(store.t(store.gattDiagnostics)).font(.caption.monospaced()).textSelection(.enabled)
                    ForEach(store.deviceInformation.keys.sorted(),id: \.self) { key in Text(store.t("\(key): \(store.deviceInformation[key] ?? "")")).font(.caption) }
                    Text(store.t(store.buttonMessage)).font(.caption)
                    Text(store.t(store.ledSummary)).font(.caption)
                }
            }
            Section {
                Button(store.t("退出开发者模式")) { store.switchSimulation(false); store.developerMode = false; dismiss() }.accessibilityIdentifier("leave-debug")
            }
        }.navigationTitle(store.t("开发者工具")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
        .sheet(isPresented: $integration) { NavigationStack { IntegrationView() } }
    }
}
struct MockControlsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reset = false
    var body: some View {
        Form {
            if let mock = store.mockDevice, store.isSimulation {
                Section {
                    Text(store.t("模拟设备 · 非真实摄入")).font(.headline)
                    Text(store.t("\(store.todayBiteCount) 口 · \(String(format: "%.0f",store.daily.kcal)) kcal · \(store.daily.pending) 口待完善"))
                        .accessibilityIdentifier("mock-totals")
                    Text(store.t(mock.status)).font(.caption).accessibilityIdentifier("mock-status")
                    Text(store.t("电源：\(mock.poweredOn ? "开" : "关") · 队列：\(mock.queuedCount) · 模拟灯：\(mock.light.map { $0 == .red ? "红" : "绿" } ?? "灭")"))
                        .font(.caption).accessibilityIdentifier("mock-device-status")
                }
                Section(store.t("连接与用餐")) {
                    Button(store.t("连接 / 同步模拟设备")) { mock.connect() }.accessibilityIdentifier("mock-connect")
                    Button(store.t("断开连接")) { mock.disconnect() }.accessibilityIdentifier("mock-disconnect")
                    Button(store.t(store.activeIntegrationMealID == nil ? "开始模拟用餐" : "模拟用餐已开启")) { _ = store.ensureIntegrationMeal() }
                        .disabled(store.activeIntegrationMealID != nil).accessibilityIdentifier("mock-start-meal")
                }
                Section(store.t("实体手势的模拟事件")) {
                    Button(store.t("短按一次 · 松手")) { mock.shortPress() }.accessibilityIdentifier("mock-short")
                    Button(store.t("重发上一事件")) { mock.replayLast() }.accessibilityIdentifier("mock-replay")
                    Button(store.t("长按一次 · 开 / 关机")) { mock.longPress() }.accessibilityIdentifier("mock-long")
                }
                Section(store.t("证据与异常")) {
                    Toggle(store.t("提供模拟份量"),isOn: Binding(get: { mock.includePortion },set: { mock.includePortion = $0 })).accessibilityIdentifier("mock-portion")
                    Text(store.t("每口模拟 10 g × 测试密度 100 kcal/100g = 10 kcal。仅验证算术，不是米饭营养数据。关闭后新事件保留待完善。"))
                        .font(.caption)
                    Toggle(store.t("模拟同步失败"),isOn: Binding(get: { mock.failSync },set: { mock.failSync = $0 })).accessibilityIdentifier("mock-failure")
                    Button(store.t("设测试目标 20 kcal")) { store.setDailyGoal(20) }.accessibilityIdentifier("mock-goal")
                    Button(store.t("结束模拟用餐")) { if let id = store.activeIntegrationMealID { store.endMeal(mealId: id) } }.accessibilityIdentifier("mock-end")
                }
                Section {
                    Button(store.t("清空隔离模拟记录"),role: .destructive) { reset = true }.accessibilityIdentifier("mock-reset")
                }
            } else { Text(store.t("先在开发者工具开启模拟设备模式。")) }
        }.navigationTitle(store.t("模拟餐勺")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
        .alert(store.t("清空模拟记录？"),isPresented: $reset) {
            Button(store.t("清空"),role: .destructive) { store.resetSimulation() }
            Button(store.t("取消"),role: .cancel) {}
        } message: { Text(store.t("仅影响隔离的演示数据，真实记录不受影响。")) }
    }
}
#endif
