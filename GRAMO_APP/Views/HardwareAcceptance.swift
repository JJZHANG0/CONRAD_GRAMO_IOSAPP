import SwiftUI

extension View {
    /// Explicit local lab launch only. Never enabled in Release or mock mode.
    @ViewBuilder func hardwareAcceptance(store: AppStore) -> some View {
        #if DEBUG
        modifier(HardwareAcceptanceModifier(store: store))
        #else
        self
        #endif
    }
}
#if DEBUG
private struct HardwareAcceptanceModifier: ViewModifier {
    let store: AppStore
    @State private var showMeal = false
    func body(content: Content) -> some View {
        content.task {
            guard ProcessInfo.processInfo.arguments.contains("-hardware-acceptance"), !store.isSimulation else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            store.startScan()
            var selected = false
            for _ in 0..<80 {
                if Task.isCancelled { return }
                if store.deviceReady, store.nomiCapabilities?.button == true {
                    _ = store.ensureIntegrationMeal(); showMeal = true; return
                }
                if !selected, let device = store.nearby.first(where: {
                    $0.name == "NOMI01" && $0.advertisedServices.contains(where: { $0.uppercased() == "6C2E0001-5B4A-4E3F-8D2C-1A0B9E8D7C6B" })
                }) {
                    selected = true; store.connectNearby(device.id)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            store.flash("未能连接餐勺，请在设备页重新连接。")
        }.onDisappear {
            if ProcessInfo.processInfo.arguments.contains("-hardware-acceptance") { UIApplication.shared.isIdleTimerDisabled = false }
        }.sheet(isPresented: $showMeal) {
            NavigationStack {
                MealExperienceView()
                    .safeAreaInset(edge: .top) {
                        Text(store.language == .en ? "PHYSICAL DEVICE TEST · REAL BUTTON REQUIRED" : "实体设备验收 · 需要真实按键")
                            .font(.caption2).padding(8).frame(maxWidth: .infinity).background(.thinMaterial)
                    }
            }
        }
    }
}
#endif
