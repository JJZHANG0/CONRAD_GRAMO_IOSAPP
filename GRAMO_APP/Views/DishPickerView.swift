import SwiftUI
import PhotosUI
import AVFoundation

struct DishPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var region: CGRect?
    @State private var selectingRegion = false
    @State private var imageID: String?
    @State private var candidates: [FoodCandidate] = []
    @State private var busy = false
    @State private var requestID = UUID()
    @State private var awaitingFrame = false
    @State private var phoneCamera = false
    @State private var source = "相册照片"
    @State private var message = "拍一张这餐的菜，也可以直接输入菜名。"
    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: "ON YOUR PLATE",title: "这餐，吃点什么？")
                Text(store.t(message)).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(5)
                HStack {
                    TextField(store.t("输入菜名"),text: $name).font(.system(size: 18)).accessibilityIdentifier("dish-name")
                    Button(store.t("选好了")) {
                        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        choose(FoodCandidate(id: UUID().uuidString,name: clean,rawLabel: clean,confidence: nil,source: "用户选菜",modelVersion: "manual-v1",imageID: nil,region: nil))
                    }.font(.system(size: 14,weight: .semibold)).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("confirm-dish")
                }.padding(20).background(.white,in: RoundedRectangle(cornerRadius: 18))
                HStack(spacing: 12) {
                    Button { captureSpoon() } label: { captureButton("餐勺拍摄",symbol: "camera.aperture") }.disabled(!store.radio.canCapture || busy).opacity(store.radio.canCapture ? 1 : 0.35).accessibilityIdentifier("capture-plate")
                    Button { openPhoneCamera() } label: { captureButton("手机拍摄",symbol: "camera") }.disabled(busy)
                    PhotosPicker(selection: $photo,matching: .images) { captureButton("从相册选",symbol: "photo") }.disabled(busy).accessibilityIdentifier("choose-photo")
                }.buttonStyle(ProductPressStyle())
                if !store.radio.canCapture { Text(store.t(store.isSimulation ? "模拟模式可使用相册中的真实照片。" : "连接支持拍摄的餐勺后，可直接拍下盘面。")) .font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                if let image {
                    VStack(alignment: .leading,spacing: 12) {
                        Text(store.t(source)).font(.system(size: 11,weight: .medium)).foregroundStyle(Palette.secondary)
                        RegionImage(image: image,region: $region,selectionEnabled: selectingRegion).clipShape(RoundedRectangle(cornerRadius: 18))
                        Button(store.t(selectingRegion ? "完成圈选" : "多道菜？圈选其中一道")) { selectingRegion.toggle() }.font(.system(size: 13,weight: .medium))
                        if selectingRegion { Text(store.t("在照片上拖出一个区域，再点完成圈选。")).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                        PrimaryButton(title: busy ? "正在看看这道菜…" : "看看是什么菜",enabled: !busy,identifier: "recognize-dish") { recognize() }.id("recognition-action")
                        if region != nil { Button(store.t("使用整张照片")) { region = nil; candidates = [] }.font(.system(size: 12)) }
                    }
                }
                if !candidates.isEmpty {
                    Text(store.t("你想记录的是哪一道？")).font(.system(size: 18,weight: .medium)).id("dish-options")
                    ForEach(candidates) { candidate in
                        Button { choose(candidate) } label: {
                            HStack { Text(candidate.displayName(in: store.language)).font(.system(size: 17,weight: .medium)); Spacer(); Text(store.t("选择")).font(.system(size: 13)); Image(systemName: "chevron.right").font(.system(size: 11)) }
                                .padding(20).background(.white,in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(ProductPressStyle())
                    }
                    Text(store.t("都不合适？在上方输入菜名就好。")).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }.padding(24)
        }
        .onChange(of: imageID) { _, id in
            if id != nil { withAnimation { reader.scrollTo("recognition-action",anchor: .bottom) } }
        }
        .onChange(of: candidates.count) { _, count in
            if count > 0 { withAnimation { reader.scrollTo("dish-options",anchor: .top) } }
        }
        }.pageBackground().simulationContext().navigationTitle(store.t("选择菜品")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("取消")) { dismiss() } } }
        .task { try? await FoodRecognizer.shared.warmUp() }
        .onDisappear { requestID = UUID(); busy = false }
        .fullScreenCover(isPresented: $phoneCamera) { PhoneCamera { accept($0,source: "iPhone 相机") }.ignoresSafeArea() }
        .onChange(of: photo) { _, new in Task {
            guard let data = try? await new?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
            accept(image,source: "手机相册")
        } }
        .onChange(of: region) { _, _ in candidates = [] }
        .onChange(of: store.spoonFrame?.id) { _, _ in
            guard awaitingFrame, let frame = store.spoonFrame, let image = UIImage(data: frame.data) else { return }
            awaitingFrame = false; accept(image,source: "餐勺相机")
        }
        .onChange(of: store.cameraBusy) { _, active in
            if !active && awaitingFrame { awaitingFrame = false; busy = false; message = "暂时没有取得照片，可以重试或直接输入菜名。" }
        }
    }
    private func captureButton(_ title: String,symbol: String) -> some View {
        VStack(spacing: 10) { Image(systemName: symbol).font(.system(size: 23,weight: .light)); Text(store.t(title)).font(.system(size: 11)) }.frame(maxWidth: .infinity).padding(.vertical,20).background(.white,in: RoundedRectangle(cornerRadius: 18))
    }
    private func choose(_ dish: FoodCandidate) { store.confirmCandidate(dish); store.flash("已选好 · \(dish.name)"); dismiss() }
    private func captureSpoon() { awaitingFrame = true; busy = true; store.radio.captureFrame() }
    private func openPhoneCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { message = "当前环境无法拍照，可以选择相册照片。"; return }
        Task { if await AVCaptureDevice.requestAccess(for: .video) { phoneCamera = true } else { message = "请在系统设置允许相机权限，或选择相册照片。" } }
    }
    private func accept(_ value: UIImage,source: String) {
        let token = UUID(); requestID = token
        self.source = source; region = nil; candidates = []; busy = true; selectingRegion = false
        let folder = store.dataDirectory.appendingPathComponent("Keyframes")
        Task {
            do {
                let prepared = try await FoodRecognizer.shared.preparePhoto(value, directory: folder)
                guard requestID == token else { return }
                image = prepared.image; imageID = prepared.id; busy = false
                message = "照片只留在本机。确认菜名后，就可以开始记录。"
            } catch {
                guard requestID == token else { return }
                busy = false; message = "照片暂时无法保存，可以手动输入菜名。"
            }
        }
    }
    private func recognize() {
        guard let image else { return }
        let id = imageID, selected = region, origin = source
        let token = UUID(); requestID = token
        busy = true; candidates = []; selectingRegion = false
        Task {
            defer { if requestID == token { busy = false } }
            do {
                let result = try await FoodRecognizer.shared.recognize(image,region: selected,source: origin,imageID: id)
                guard requestID == token, id == imageID, selected == region else { return }
                candidates = result.candidates; message = "请选择与你这道菜相符的名称。"
            } catch { if requestID == token { message = "暂时无法辨认这道菜，手动输入名称也一样可以记录。" } }
        }
    }
}
