import SwiftUI
import PhotosUI
import AVFoundation

#if DEBUG
struct IntegrationSummary: View {
    @Environment(AppStore.self) private var store
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t(store.dailySummary))
                .font(.system(size: 15)).accessibilityIdentifier("integration-total")
            if store.daily.legacyItems > 0 { Text(store.t("含 \(store.daily.legacyItems) 项旧记录，保留原值，核实来源后计入目标。")).font(.caption).foregroundStyle(Palette.secondary) }
            Text(store.t(goalText)).font(.caption).foregroundStyle(Palette.secondary)
            Text(store.t(store.ledSummary)).font(.caption).foregroundStyle(Palette.secondary)
            if let latest = store.latestIntake {
                Text(store.t("最近一口 · \(latest.dish?.name ?? "待确认") · \(latest.grams.map { String(format: "约 %.1f g", $0) } ?? "重量待确认") · \(store.state.hideCalories ? "热量已隐藏" : (latest.estimatedKcal.map { String(format: "约 %.1f kcal", $0) } ?? "热量待确认"))"))
                    .font(.caption).accessibilityIdentifier("latest-intake")
            }
            TextAction(title: "拍盘、逐口记录与每日目标") { open = true }
                .accessibilityIdentifier("open-integration")
        }
        .padding(16).background { GlassShape(radius: 22) }
        .sheet(isPresented: $open) { NavigationStack { IntegrationView() } }
    }
    private var goalText: String {
        guard let goal = store.settings.dailyGoal, let color = store.daily.color(goal: goal) else { return "每日目标未设置" }
        return String(format: "目标 %.1f kcal · 应显示%@", goal, color == .red ? "红灯（达到目标）" : "绿灯（低于目标）")
    }
}

struct IntegrationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var imageID: String?
    @State private var source = "手机相册（降级模式）"
    @State private var screenRecapture = false
    @State private var camera = false
    @State private var region: CGRect?
    @State private var candidates: [FoodCandidate] = []
    @State private var message = "勺载相机通道尚未核实，当前使用 iPhone 拍盘。"
    @State private var busy = false
    @State private var manualName = ""
    @State private var goal = ""
    @State private var bite = false
    @State private var editing: IntakeEvidence?
    @State private var deleteKey: String?
    @State private var legacyEdit: LegacyIntake?
    @State private var awaitingPlate = false
    @State private var showPreview = true
    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.t("本餐候选菜")).font(.title2)
                Text(store.t(message)).font(.footnote).foregroundStyle(Palette.secondary)
                HStack {
                    Button(store.t("手机拍盘")) { openCamera() }.accessibilityIdentifier("capture-plate")
                    Spacer()
                    PhotosPicker("选择照片", selection: $photo, matching: .images)
                }
                Toggle(store.t("屏幕翻拍测试（非真实盘面）"), isOn: $screenRecapture).font(.caption)
                if store.nomiCapabilities != nil {
                    if showPreview { SpoonPreview(owner: "integration") }
                    Button(store.t(showPreview ? "收起连续预览，专注盘面确认" : "显示勺载连续预览")) { showPreview.toggle() }
                    Button(store.t("从勺载画面抓取开餐图")) {
                        if let frame = store.spoonFrame, Date().timeIntervalSince(frame.timestamp) <= 6, let image = UIImage(data: frame.data) {
                            acceptImage(image, source: "NOMI01 勺载相机 · \(frame.timestamp.ISO8601Format())")
                        } else { awaitingPlate = true; store.radio.captureFrame() }
                    }.disabled(!store.radio.canCapture).accessibilityIdentifier("capture-spoon")
                    Text(store.t(store.cameraMessage)).font(.caption)
                    Text(store.t(store.buttonMessage)).font(.footnote)
                    if store.activeIntegrationMealID == nil {
                        Button(store.t("开始用餐，启用实体短按")) { _ = store.ensureIntegrationMeal() }
                    }
                }
                if let image {
                    RegionImage(image: image, region: $region)
                    Text(store.t("多道菜请逐块拖选，识别并确认后再选下一块。Top 3 是一个区域的备选名称。")).font(.caption)
                    HStack {
                        Button(store.t("识别选区")) { recognize() }.disabled(busy)
                        Spacer()
                        Button(store.t("整图单菜")) { region = nil; recognize() }.disabled(busy)
                    }
                }
                if busy { ProgressView("本机识别中") }
                ForEach(candidates) { candidate in
                    Button {
                        store.confirmCandidate(candidate); candidates = []; message = "已加入本餐候选。换菜时请重新选择当前菜品。"
                    } label: {
                        HStack { Text(candidate.displayName(in: store.language)); Spacer(); Text(store.t(String(format: "%.1f%%", (candidate.confidence ?? 0)*100))) }
                    }
                }.id("recognition-results")
                HStack {
                    TextField(store.t("手动输入菜名 / 库外菜"), text: $manualName).textFieldStyle(.roundedBorder)
                    Button(store.t("确认")) {
                        store.confirmCandidate(FoodCandidate(id: UUID().uuidString, name: manualName.trimmingCharacters(in: .whitespacesAndNewlines), rawLabel: manualName,
                                                             confidence: nil, source: "人工确认", modelVersion: "manual-v1", imageID: imageID,
                                                             region: region.map { [$0.minX,$0.minY,$0.width,$0.height] }))
                        manualName = ""
                    }.disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(store.settings.candidates) { candidate in
                    Button { store.selectDish(candidate.id) } label: {
                        HStack { Text(candidate.displayName(in: store.language)); Spacer(); if candidate.id == store.settings.currentDishID { Image(systemName: "checkmark") } }
                    }
                }
                PrimaryButton(title: "人工补录 / 修正一口", identifier: "record-bite") { _ = store.ensureIntegrationMeal(); bite = true }
                if let id = store.settings.mealID, store.state.meals.contains(where: { $0.id == id && $0.status == .recording }) {
                    Button(store.t("结束本餐（不重复入账）")) { store.endMeal(mealId: id) }
                }
                Hairline()
                Text(store.t("每日目标")).font(.title2)
                HStack {
                    TextField(store.t("kcal，留空取消"), text: $goal).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier("daily-goal")
                    Button(store.t("保存目标")) {
                        if goal.trimmingCharacters(in: .whitespaces).isEmpty { store.setDailyGoal(nil) }
                        else if let value = Double(goal), value.isFinite, value > 0, value <= 100_000 { store.setDailyGoal(value) }
                        else { message = "请输入有效的正数目标。" }
                    }.accessibilityIdentifier("save-daily-goal")
                }
                Text(store.t(store.dailySummary)).font(.footnote)
                Text(store.t("目标状态：\(store.daily.color(goal: store.settings.dailyGoal).map { $0 == .red ? "红" : "绿" } ?? "未设置") · \(store.ledSummary)")).font(.footnote).accessibilityIdentifier("goal-color")
                if store.radio.canControlLED { Button(store.t("重新同步设备与实体灯")) { store.resyncLED() } }
                Text(store.t("逐口记录 · 点击修正")).font(.title2)
                ForEach(legacyItems) { entry in
                    Button(store.t("核实旧记录：\(entry.food.name) · \(entry.meal.date)")) { legacyEdit = entry }
                        .font(.footnote)
                }
                ForEach(intakes, id: \.key) { entry in
                    HStack {
                        Button { editing = entry } label: {
                            VStack(alignment: .leading) {
                                Text(store.t(entry.dish?.name ?? "菜品待确认"))
                                Text(store.t("\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(entry.estimatedKcal.map { String(format: "约 %.1f kcal", $0) } ?? "待确认")")).font(.caption)
                            }
                        }
                        Spacer()
                        Button(store.t("删除"), role: .destructive) { deleteKey = entry.key }.font(.caption)
                    }
                }
            }.padding(24)
        }
        .onChange(of: candidates.count) { _, count in
            if count > 0 { withAnimation { reader.scrollTo("recognition-results", anchor: .center) } }
        }
        }
        .tint(Palette.ink).pageBackground().navigationTitle(store.t("开餐与联调"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
        .onAppear {
            goal = store.settings.dailyGoal.map { String(format: "%.1f", $0) } ?? ""; store.refreshDay()
            if store.radio.canCapture { message = "可拍摄真实勺载关键帧，或用 iPhone 拍盘。请先确认镜头能看清食物。" }
        }
        .onChange(of: store.spoonFrame?.id) { _, _ in
            guard awaitingPlate, let frame = store.spoonFrame, let image = UIImage(data: frame.data) else { return }
            awaitingPlate = false
            acceptImage(image, source: "NOMI01 勺载相机 · \(frame.deviceID) · \(frame.timestamp.ISO8601Format())")
        }
        .onChange(of: photo) { _, value in
            Task {
                guard let data = try? await value?.loadTransferable(type: Data.self), let loaded = UIImage(data: data) else { return }
                acceptImage(loaded, source: "手机相册（降级模式）")
            }
        }
        .onChange(of: region) { _, _ in
            if !candidates.isEmpty {
                candidates = []
                message = "菜品区域已改变，请重新识别后确认。"
            }
        }
        .fullScreenCover(isPresented: $camera) { PhoneCamera { acceptImage($0, source: "iPhone 相机（降级模式）") }.ignoresSafeArea() }
        .sheet(isPresented: $bite) { NavigationStack { IntakeEditor(existing: nil) } }
        .sheet(item: $editing) { entry in NavigationStack { IntakeEditor(existing: entry) } }
        .sheet(item: $legacyEdit) { entry in NavigationStack { IntakeEditor(existing: entry.evidence, legacy: entry) } }
        .alert(store.t("删除这口记录？"), isPresented: Binding(get: { deleteKey != nil }, set: { if !$0 { deleteKey = nil } })) {
            Button(store.t("删除"), role: .destructive) { if let deleteKey { store.removeIntake(deleteKey) }; deleteKey = nil }
            Button(store.t("取消"), role: .cancel) { deleteKey = nil }
        }
    }
    private var legacyItems: [LegacyIntake] {
        store.state.meals.flatMap { meal in meal.foods.filter { $0.evidence == nil }.map { LegacyIntake(meal: meal, food: $0) } }
    }
    private var intakes: [IntakeEvidence] { store.state.meals.flatMap(\.foods).compactMap(\.evidence).sorted { $0.timestamp > $1.timestamp } }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { message = "此环境没有相机，请选择真实照片。"; return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { camera = true } else { message = "相机权限未开放，可在系统设置开启或选择照片。" }
        }
    }
    private func acceptImage(_ loaded: UIImage, source: String) {
        showPreview = false
        image = FoodRecognizer.upright(loaded); region = nil; candidates = []; self.source = source
        imageID = nil
        do {
            let folder = store.dataDirectory.appendingPathComponent("Keyframes")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let id = UUID().uuidString + ".jpg"
            guard let data = image?.jpegData(compressionQuality: 0.9) else { throw RecognitionError.invalidImage }
            try data.write(to: folder.appendingPathComponent(id), options: [.atomic, .completeFileProtection])
            imageID = id; message = "关键帧已保存在本机，未上传。请选择单道菜区域。"
        } catch { message = "关键帧保存失败：\(error.localizedDescription)" }
    }
    private func recognize() {
        guard let image else { return }; busy = true; candidates = []
        let requestedRegion = region, requestedSource = source + (screenRecapture ? " · 屏幕翻拍测试" : ""), requestedID = imageID
        Task {
            defer { busy = false }
            do {
                let result = try await FoodRecognizer.shared.recognize(image, region: requestedRegion, source: requestedSource, imageID: requestedID, diagnosticDirectory: store.dataDirectory)
                guard requestedID == imageID, requestedRegion == region else { return }
                candidates = result.candidates; message = result.note
            } catch { message = error.localizedDescription }
        }
    }
}
// Developer instrumentation is excluded from Release. Shared editing/camera views remain.
#endif
extension IntakeEvidence: Identifiable { var id: String { key } }

struct IntakeEditor: View {
    var existing: IntakeEvidence?
    var legacy: LegacyIntake? = nil
    var targetMealID: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var grams = ""
    @State private var density = ""
    @State private var nutrition = ""
    @State private var confirmed = false
    @State private var error = ""
    @State private var eventID = UUID().uuidString
    @State private var when = Date()
    @State private var initialName = ""
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section(store.t("菜品与份量")) {
                TextField(store.t("菜名，可暂缺"), text: $name).accessibilityIdentifier("bite-name")
                TextField(store.t("厨房秤或人工输入克数，可暂缺"), text: $grams).keyboardType(.decimalPad).accessibilityIdentifier("bite-grams")
                TextField(store.t("参考 kcal/100g，可暂缺"), text: $density).keyboardType(.decimalPad).accessibilityIdentifier("bite-density")
                TextField(store.t("营养来源：包装标签 / 数据库条目"), text: $nutrition).accessibilityIdentifier("bite-nutrition-source")
                DatePicker(store.t("时间"), selection: $when)
                Toggle(store.t("确认这一口已吃下"), isOn: $confirmed).accessibilityIdentifier("bite-eaten")
            }
            Section {
                Text(store.t("当前为人工补录。菜名、克数、能量密度和来源齐全且确认吃下才计入。倒回、掉落、只舀未吃请取消，或保留为待确认。做法、油和酱汁会改变热量。"))
                if let existing, store.developerMode { Text(store.t(existing.note)); Text(store.t("测量方式：\(existing.measurement)")) }
                if let frames = existing?.frames, !frames.isEmpty {
                    ForEach(frames) { frame in
                        VStack(alignment: .leading) {
                            Text(store.t("\(frame.phase == "before" ? "短按前附近画面" : "短按后附近画面") · \(frame.timestamp.formatted(date: .omitted, time: .standard))"))
                            if let image = UIImage(contentsOfFile: store.dataDirectory.appendingPathComponent(frame.relativePath).path) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                            }
                        }
                    }
                }
                if !error.isEmpty { Text(store.t(error)) }
                Button(store.t("保存这一口")) { save() }.accessibilityIdentifier("save-bite")
            }
        }.tint(Palette.ink).simulationContext().navigationTitle(store.t(existing == nil ? "记录一口" : "修正这一口"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("取消")) { dismiss() } }
                if existing != nil, legacy == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(store.t("删除这一口")).accessibilityIdentifier("delete-bite")
                    }
                }
            }
            .onAppear {
                name = existing?.dish?.name ?? store.currentDish?.name ?? ""
                grams = existing?.grams.map { String($0) } ?? ""
                density = existing?.kcalPer100g.map { String($0) } ?? ""
                nutrition = existing?.nutritionSource ?? ""
                confirmed = existing?.confirmedEating ?? false
                let targetDate = targetMealID.flatMap { id in store.state.meals.first { $0.id == id } }.map { Date(timeIntervalSince1970: $0.startedAt/1000) }
                when = existing?.timestamp ?? targetDate ?? Date()
                initialName = name
            }
            .alert(store.t("删除这一口？"),isPresented: $confirmDelete) {
                Button(store.t("删除"),role: .destructive) { if let existing { store.removeIntake(existing.key) }; dismiss() }
                Button(store.t("取消"),role: .cancel) {}
            } message: { Text(store.t("今日累计会重新计算。重复同步不会恢复已删除的口次。")) }
            .onChange(of: name) { _, value in
                if value != initialName { density = ""; nutrition = "" }
            }
    }
    private func save() {
        let weight = Double(grams), kcal = Double(density)
        guard grams.isEmpty || (weight?.isFinite == true && weight! > 0 && weight! <= 500),
              density.isEmpty || (kcal?.isFinite == true && kcal! > 0 && kcal! <= 1000) else { error = "克数需为 0–500 的正数；能量密度需为 0–1000 的正数。空勺不入账。"; return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var dish = existing?.dish ?? store.currentDish
        if dish?.name != trimmed {
            dish = trimmed.isEmpty ? nil : FoodCandidate(id: UUID().uuidString, name: trimmed, rawLabel: trimmed, confidence: nil,
                                                         source: "人工修正", modelVersion: "manual-v1", imageID: dish?.imageID, region: dish?.region)
        }
        let evidence = IntakeEvidence(eventID: existing?.eventID ?? eventID, deviceID: existing?.deviceID ?? "manual", timestamp: when,
                                      dish: dish, grams: weight, kcalPer100g: kcal, nutritionSource: nutrition,
                                      measurement: "人工输入克数", confirmedEating: confirmed, corrected: existing != nil,
                                      note: existing?.note ?? "用户逐口确认；无自动传感器测量。", frames: existing?.frames)
        if let legacy {
            store.reconcileLegacy(mealID: legacy.meal.id, foodID: legacy.food.id, evidence: evidence)
        } else if let existing, let meal = store.state.meals.first(where: { $0.foods.contains(where: { $0.evidence?.key == existing.key }) }) {
            store.saveIntake(evidence, mealID: meal.id, correction: true)
        } else { store.saveIntake(evidence, mealID: targetMealID) }
        dismiss()
    }
}

struct RegionImage: View {
    let image: UIImage
    @Binding var region: CGRect?
    var selectionEnabled = true
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image).resizable().scaledToFit()
                .overlay(alignment: .topLeading) {
                    if let region {
                        Rectangle().stroke(.white, lineWidth: 2).background(.black.opacity(0.12))
                            .frame(width: region.width*proxy.size.width, height: region.height*proxy.size.height)
                            .offset(x: region.minX*proxy.size.width, y: region.minY*proxy.size.height)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { value in
                    let a = CGPoint(x: min(max(value.startLocation.x/proxy.size.width,0),1), y: min(max(value.startLocation.y/proxy.size.height,0),1))
                    let b = CGPoint(x: min(max(value.location.x/proxy.size.width,0),1), y: min(max(value.location.y/proxy.size.height,0),1))
                    region = CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: max(abs(a.x-b.x),0.01), height: max(abs(a.y-b.y),0.01))
                }, including: selectionEnabled ? .all : .none)
        }.aspectRatio(image.size.width/image.size.height, contentMode: .fit)
    }
}
struct PhoneCamera: UIViewControllerRepresentable {
    var receive: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhoneCamera
        init(_ parent: PhoneCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.receive(image) }; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct LegacyIntake: Identifiable {
    var meal: Meal
    var food: FoodItem
    var id: String { meal.id + ":" + food.id }
    var evidence: IntakeEvidence {
        IntakeEvidence(eventID: id, deviceID: "legacy-confirmed", timestamp: Date(timeIntervalSince1970: ZWFormat.atTime(meal.date, meal.time)/1000),
                       dish: FoodCandidate(id: food.id, name: food.name, rawLabel: food.name, confidence: nil, source: "旧记录，人工核实", modelVersion: "manual-v1", imageID: nil, region: nil),
                       grams: nil, kcalPer100g: nil, nutritionSource: "", measurement: "人工核实旧记录", confirmedEating: false,
                       corrected: true, note: "原记录：\(food.name)，\(food.portion)，\(food.kcal.map { String($0) } ?? "未知") kcal；未沿用未经核实的旧估算。")
    }
}
