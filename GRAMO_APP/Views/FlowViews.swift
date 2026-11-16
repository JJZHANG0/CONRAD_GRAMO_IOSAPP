import SwiftUI

struct CorrectionView: View {
    var mealId: String
    var foodId: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId = ""

    var body: some View {
        let vm = Present.correction(store.state, mealId: mealId, foodId: foodId, language: store.language)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !vm.mealName.isEmpty {
                    Text(store.t("\(vm.mealName) · \(vm.foodName)"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.secondary)
                }
                Text(store.t(vm.prompt))
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
                QuietNote(text: store.t("选择一项后，本餐合计会跟着更新。可以稍后再次修改。"))
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(vm.options) { option in
                        Button {
                            selectedId = option.id
                        } label: {
                            HStack {
                                Text(store.t(option.label))
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if selectedId == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("option-\(option.id)")
                        Hairline()
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: store.t("保存并更新本餐"), enabled: !selectedId.isEmpty && !vm.missing, identifier: "save-correction") {
                guard !selectedId.isEmpty, !vm.missing else { return }
                store.saveCorrection(mealId: mealId, foodId: foodId, optionId: selectedId)
                dismiss()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onAppear {
            if selectedId.isEmpty { selectedId = vm.choiceId }
        }
    }
}

struct AddEntryView: View {
    var mealId: String
    var date: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var portion = ""
    @State private var chosenDate = ""
    @State private var time = ""
    @State private var mealName = "加餐"
    @State private var error = ""

    private let mealNames = ["早餐", "午餐", "晚餐", "加餐"]
    private var lockedMeal: Meal? {
        guard !mealId.isEmpty else { return nil }
        return store.state.meals.first { $0.id == mealId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("补录"))
                    .font(.system(size: 34, weight: .regular))
                Text(store.t("饮品、零食，或餐具没有记下的食物，都可以补在这里。"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
                if let meal = lockedMeal {
                    QuietNote(text: store.t("加入\(meal.name)"))
                        .padding(.top, 8)
                }
                FieldLabel(text: store.t("食物名称")).padding(.top, 28)
                LineField(placeholder: store.t("例如 苹果、黑咖啡"), text: $name)
                FieldLabel(text: store.t("分量")).padding(.top, 20)
                LineField(placeholder: store.t("例如 1 个，可不填"), text: $portion)
                QuietNote(text: store.t("不填分量，或还不能估算的食物，会保持待估算。"))
                    .padding(.top, 8)

                if lockedMeal == nil {
                    FieldLabel(text: store.t("日期")).padding(.top, 20)
                    Text(store.t(L10n.dateLine(chosenDate.isEmpty ? ZWFormat.formatISODate(Date()) : chosenDate, week: true, store.language)))
                        .font(.system(size: 17, weight: .regular))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                        .overlay {
                            DatePicker(store.t(""), selection: dateBinding, displayedComponents: .date)
                                .labelsHidden()
                                .colorMultiply(.clear)
                        }
                    FieldLabel(text: store.t("餐次")).padding(.top, 20)
                    Picker(store.t("餐次"), selection: $mealName) {
                        ForEach(mealNames, id: \.self) { Text(store.t($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                }

                FieldLabel(text: store.t("时间")).padding(.top, 20)
                Text(store.t(time.isEmpty ? ZWFormat.formatClock(Date()) : time))
                    .font(.system(size: 17, weight: .regular))
                    .monospacedDigit()
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Hairline() }
                    .overlay {
                        DatePicker(store.t(""), selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorMultiply(.clear)
                    }
                if !error.isEmpty {
                    Text(store.t(error))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 12)
                }
                PrimaryButton(title: store.t(lockedMeal == nil ? "加入这条记录" : "保存并更新本餐"), identifier: "save-entry") {
                    save()
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            let now = Date()
            if let meal = lockedMeal {
                chosenDate = meal.date
                time = meal.time
                mealName = meal.name
            } else {
                chosenDate = date.isEmpty ? ZWFormat.formatISODate(now) : date
                time = ZWFormat.formatClock(now)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ZWFormat.parseISODate(chosenDate.isEmpty ? ZWFormat.formatISODate(Date()) : chosenDate) },
            set: { chosenDate = ZWFormat.formatISODate($0) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let iso = chosenDate.isEmpty ? ZWFormat.formatISODate(Date()) : chosenDate
                let clock = time.isEmpty ? ZWFormat.formatClock(Date()) : time
                return Date(timeIntervalSince1970: ZWFormat.atTime(iso, clock) / 1000)
            },
            set: { time = ZWFormat.formatClock($0) }
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            error = "请先写食物名称"
            return
        }
        _ = store.addFood(AddFoodInput(
            mealId: mealId,
            date: chosenDate,
            mealName: mealName,
            time: time,
            name: trimmed,
            portion: portion
        ))
        dismiss()
    }
}

struct PreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var height = ""
    @State private var weight = ""
    @State private var goal = ""
    private let goals = ["吃得更规律", "把每餐记完整", "清淡一些", "暂不设定"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("个人偏好"))
                    .font(.system(size: 34, weight: .regular))
                Text(store.t("都可以留空，不会拦住记录。"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
                FieldLabel(text: store.t("身高")).padding(.top, 28)
                LineField(placeholder: store.t("厘米，可不填"), text: $height)
                FieldLabel(text: store.t("体重")).padding(.top, 20)
                LineField(placeholder: store.t("公斤，可不填"), text: $weight)
                FieldLabel(text: store.t("想先关注什么")).padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(goals, id: \.self) { item in
                        Button {
                            goal = item
                        } label: {
                            HStack {
                                Text(store.t(item))
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if goal == item {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }
                .padding(.top, 8)
                PrimaryButton(title: store.t("保存"), identifier: "save-profile") {
                    store.saveProfile(heightCm: height, weightKg: weight, goal: goal)
                    dismiss()
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            height = store.state.profile.heightCm
            weight = store.state.profile.weightKg
            goal = store.state.profile.goal
        }
    }
}

struct PrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmDelete = false
    @State private var exportURL: URL?
    @State private var exportFailed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: "YOURS, ALWAYS",title: "你的日常，由你保管")
                Surface {
                    VStack(alignment: .leading,spacing: 14) {
                        Image(systemName: "lock.shield").font(.system(size: 29,weight: .light))
                        Text(store.t("记录保存在本机")).font(.system(size: 20,weight: .medium))
                        Text(store.t("照片和用餐记录不会自动上传。识别在设备上完成；相机仅在你打开画面或前台用餐时采集。"))
                            .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    }
                }
                Surface {
                    VStack(alignment: .leading,spacing: 14) {
                        Text(store.t("带走你的记录")).font(.system(size: 18,weight: .medium))
                        Text(store.t("导出本机的用餐记录、个人资料与每日目标。文件可能包含你的健康信息，请自行选择保管位置。"))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
                        if let exportURL { ShareLink(store.t("分享记录文件"),item: exportURL).font(.system(size: 14,weight: .medium)) }
                        else { Button(store.t("准备导出")) { prepareExport() }.font(.system(size: 14,weight: .medium)).accessibilityIdentifier("prepare-export") }
                        if exportFailed { Text(store.t("文件暂时无法生成，请稍后再试。")).font(.footnote) }
                    }
                }
                Surface {
                    VStack(alignment: .leading,spacing: 14) {
                        Text(store.t("清除本机记录")).font(.system(size: 18,weight: .medium))
                        Text(store.t("保留个人设置与设备信息。清除后无法在 App 内恢复，建议先导出。"))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
                        Button(store.t("删除用餐记录"),role: .destructive) { confirmDelete = true }.font(.system(size: 14)).accessibilityIdentifier("delete-meals")
                    }
                }
            }.padding(24)
        }.pageBackground()
        .alert(store.t("删除本机用餐记录？"),isPresented: $confirmDelete) {
            Button(store.t("删除"),role: .destructive) { store.deleteLocalMeals(); exportURL = nil }
            Button(store.t("取消"),role: .cancel) {}
        } message: { Text(store.t(store.isSimulation ? "仅清除当前隔离模拟环境的记录。" : "此操作无法撤销，请确认已保存需要的记录。")) }
    }
    private func prepareExport() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            let data = try encoder.encode(store.state)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("NOMI-\(store.isSimulation ? "simulation" : "records")-\(UUID().uuidString.prefix(8)).json")
            try data.write(to: url,options: [.atomic,.completeFileProtection])
            exportURL = url
        } catch { exportFailed = true }
    }
}

struct MembershipView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("基础能力现在就可以用。付费方案还没有开放购买或续费。"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
                plan("基础", "正在使用", ["连接餐具", "记录用餐", "查看历史", "核对与补录"])
                plan("Plus", "未开通", ["完整趋势", "食谱工具", "更细的用餐回顾"])
                plan("Pro", "未开通", ["在 Plus 之上，支持更长时间的回顾"])
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func plan(_ title: String, _ status: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.t(title))
                    .font(.system(size: 22, weight: .regular))
                Spacer()
                Text(store.t(status))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.tertiary)
            }
            ForEach(lines, id: \.self) { line in
                Text(store.t(line))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
            Hairline().padding(.top, 12)
        }
        .padding(.top, 28)
    }
}
