import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.navPath) private var path
    @State private var showDebug = false
    @State private var showGoal = false
    @State private var showLanguage = false
    private var days: Int { Set(store.state.meals.filter { !$0.foods.isEmpty }.map(\.date)).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 24) {
                ProductHeader(eyebrow: "MADE FOR YOUR EVERYDAY",title: "我的日常")
                HStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Palette.ink).frame(width: 66,height: 66)
                        Image(systemName: "leaf").font(.system(size: 27,weight: .ultraLight)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading,spacing: 7) {
                        Text(store.t("好好吃饭，慢慢来。")).font(.system(size: 20,weight: .medium))
                        Text(store.t(days == 0 ? "从一餐开始，建立自己的节奏。" : "已留下 \(days) 天的用餐日常。"))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }.padding(.vertical,4)
                Button { showGoal = true } label: {
                    Surface(dark: true) {
                        VStack(alignment: .leading,spacing: 22) {
                            HStack {
                                Text(store.t("我的目标")).font(.system(size: 12,weight: .medium)).foregroundStyle(.white.opacity(0.6))
                                Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                            }
                            HStack(alignment: .firstTextBaseline,spacing: 8) {
                                Text(store.t(store.settings.dailyGoal.map { String(format: "%.0f",$0) } ?? "按需设定")).font(.system(size: 36,weight: .medium)).tracking(-1).foregroundStyle(.white)
                                if store.settings.dailyGoal != nil { Text(store.t("kcal / 天")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)) }
                            }
                            Text(store.t(store.state.profile.goal == "暂不设定" || store.state.profile.goal.isEmpty ? "找到适合自己的用餐节奏" : store.state.profile.goal))
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("profile-goal")
                Surface {
                    VStack(alignment: .leading,spacing: 20) {
                        HStack { Text(store.t("健康档案")).font(.system(size: 17,weight: .semibold)); Spacer(); Button(store.t("编辑")) { path?.wrappedValue.append(AppRoute.preferences) }.font(.system(size: 12)).accessibilityIdentifier("profile-preferences") }
                        HStack {
                            Metric(value: store.state.profile.heightCm.isEmpty ? "—" : store.state.profile.heightCm,unit: "cm",title: "身高")
                            Metric(value: store.state.profile.weightKg.isEmpty ? "—" : store.state.profile.weightKg,unit: "kg",title: "体重")
                            Metric(value: "\(days)",unit: "天",title: "记录日常")
                        }
                    }
                }
                Button { path?.wrappedValue.append(AppRoute.device(.none)) } label: {
                    Surface {
                        HStack(spacing: 16) {
                            Image("ProductSpoon").resizable().scaledToFit().frame(width: 62,height: 66)
                            VStack(alignment: .leading,spacing: 8) {
                                Text(store.t("我的 NOMI")).font(.system(size: 17,weight: .medium))
                                Text(store.t(store.consumerConnection)).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                        }
                    }
                }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("profile-device")
                Surface {
                    VStack(spacing: 10) {
                        ProfileLink(title: "语言",value: store.language == .en ? "English" : "简体中文",identifier: "profile-language") { showLanguage = true }
                        Hairline()
                        ProfileLink(title: "餐具与配件",value: "探索",identifier: "profile-shop") { path?.wrappedValue.append(AppRoute.shop) }
                        Hairline()
                        ProfileLink(title: "隐私与数据",value: "保存在本机",identifier: "profile-privacy") { path?.wrappedValue.append(AppRoute.privacy) }
                        Hairline()
                        Toggle(store.t("隐藏热量数字"),isOn: Binding(get: { store.state.hideCalories },set: { store.setHideCalories($0) })).font(.system(size: 15)).tint(Palette.ink).padding(.vertical,8).accessibilityIdentifier("hide-calories")
                    }
                }
                VStack(spacing: 8) {
                    Text(store.t("N O M I")).font(.system(size: 13,weight: .medium)).foregroundStyle(Palette.secondary)
                        #if DEBUG
                        .onLongPressGesture(minimumDuration: 3) { store.developerMode = true; showDebug = true }
                        #endif
                    Text(store.t("让每一餐，多一点觉察。")).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }.frame(maxWidth: .infinity).padding(.top,8)
                #if DEBUG
                if store.developerMode {
                Button(store.t("开发者工具 · Debug")) { showDebug = true }
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary).frame(maxWidth: .infinity).padding(.vertical,8).accessibilityIdentifier("open-debug")
                }
                #endif
            }.padding(.horizontal,22).padding(.bottom,24)
        }.pageBackground().scrollIndicators(.hidden)
        .sheet(isPresented: $showLanguage) { NavigationStack { LanguageView() } }
        .sheet(isPresented: $showGoal) { NavigationStack { DailyGoalView() } }
        #if DEBUG
        .sheet(isPresented: $showDebug) { NavigationStack { DeveloperToolsView() } }
        #endif
    }
}
struct ProfileLink: View {
    @Environment(AppStore.self) private var store
    var title: String
    var value: String
    var stacksValue = false
    var identifier: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(store.t(title)).font(.system(size: 15))
                Spacer()
                Text(store.t(value)).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10,weight: .medium)).foregroundStyle(Palette.tertiary)
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(ProductPressStyle()).accessibilityIdentifier(identifier)
    }
}
struct DailyGoalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 28) {
                ProductHeader(eyebrow: "YOUR OWN PACE",title: "给日常一个方向")
                Text(store.t("目标由你决定，随时都能调整。\n这里的数字是一份记录，不是一项考核。"))
                    .font(.system(size: 15)).foregroundStyle(Palette.secondary).lineSpacing(6)
                Surface {
                    VStack(alignment: .leading,spacing: 18) {
                        Text(store.t("每日摄入目标")).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            TextField(store.t("尚未设定"),text: $value).keyboardType(.decimalPad).font(.system(size: 38,weight: .medium)).accessibilityIdentifier("daily-goal-input")
                            Text(store.t("kcal")).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                Text(store.t("仅有完整信息的口次计入进度。待完善记录补充后，今日累计与餐勺提示会一起更新。"))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5)
                if let error { Text(store.t(error)).font(.footnote).foregroundStyle(.red) }
                PrimaryButton(title: "保存目标",identifier: "save-goal") {
                    guard let number = Double(value), number.isFinite, number > 0, number <= 100000 else { error = "请输入有效的正数。"; return }
                    store.setDailyGoal(number); store.flash("每日目标已更新"); dismiss()
                }
                Button(store.t("暂不设定目标")) { store.setDailyGoal(nil); dismiss() }.font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
            }.padding(24)
        }.pageBackground().simulationContext().navigationTitle(store.t("每日目标")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
        .onAppear { value = store.settings.dailyGoal.map { String(format: "%.0f",$0) } ?? "" }
    }
}

struct LanguageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                languageOption("English", .en)
                languageOption("简体中文", .zh)
            } footer: { Text(store.t("随时切换，记录保持不变。")) }
        }
        .tint(Palette.ink).navigationTitle(store.t("语言设置"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("完成")) { dismiss() } } }
    }
    private func languageOption(_ title: String, _ language: AppLanguage) -> some View {
        Button {
            store.setLanguage(language)
            dismiss()
        } label: {
            HStack { Text(title); Spacer(); if store.language == language { Image(systemName: "checkmark") } }
                .foregroundStyle(Palette.ink).frame(minHeight: 36)
        }.accessibilityIdentifier("language-\(language.rawValue)")
    }
}
