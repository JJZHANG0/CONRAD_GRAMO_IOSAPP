import SwiftUI

struct SpoonPreview: View {
    let owner: String
    @Environment(AppStore.self) private var store
    @State private var running = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(store.deviceReady ? "设备已连接" : "设备未连接")).font(.footnote)
            if let frame = store.spoonFrame, let image = UIImage(data: frame.data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .accessibilityIdentifier("spoon-preview-image")
            }
            Text(store.t(store.cameraStatus)).font(.caption).accessibilityIdentifier("spoon-camera-status")
            Toggle(store.t("勺载画面间隔刷新（约 2 秒）"), isOn: Binding(
                get: { running || store.activeIntegrationMealID != nil },
                set: { running = $0 }
            )).font(.footnote).disabled(store.activeIntegrationMealID != nil)
            if store.activeIntegrationMealID != nil {
                Text(store.t("用餐中持续采集短按前后的关键帧；结束用餐后可暂停刷新。")).font(.caption).foregroundStyle(Palette.secondary)
            }
            Text(store.t("短按前最多保留 20 秒附近画面；仅已记录口次的关联帧保存到本机。画面不等于称重结果。")).font(.caption).foregroundStyle(Palette.secondary)
        }
        .onAppear { store.setPreview(running, owner: owner) }
        .onDisappear { store.setPreview(false, owner: owner) }
        .onChange(of: running) { _, enabled in store.setPreview(enabled, owner: owner) }
    }
}
