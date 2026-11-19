import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.navPath) private var path
    @State private var mealOpen = false
    @State private var goalOpen = false
    private var meals: [Meal] { store.state.meals.filter { meal in meal.date == store.todayISO || meal.foods.contains { $0.evidence.map { ZWFormat.formatISODate($0.timestamp) == store.todayISO } == true } }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    ProductHeader(eyebrow: L10n.dateLine(store.todayISO, week: true, store.language), title: "每一口，都算数。")
                    Spacer(minLength: 6)
                    Button { path?.wrappedValue.append(AppRoute.device(.none)) } label: {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 17, weight: .regular))
                            .frame(width: 44, height: 44).background(.white, in: Circle())
                    }.padding(.top, 14).accessibilityIdentifier("device-chip").accessibilityLabel(store.t("我的餐勺，\(store.consumerConnection)"))
                }
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.t("NOMI")).font(.system(size: 24, weight: .medium)).tracking(5)
                            Text(store.t("你的日常，轻一点。")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(store.deviceReady ? Color(red: 0.27, green: 0.48, blue: 0.38) : Palette.tertiary).frame(width: 5, height: 5)
                            Text(store.t(store.consumerConnection)).font(.system(size: 11))
                        }
                    }
                    Image("ProductSpoon").resizable().scaledToFit().frame(height: 190)
                        .rotationEffect(.degrees(12)).padding(.vertical, 2)
                        .shadow(color: .black.opacity(0.06), radius: 12, x: 2, y: 16)
                        .accessibilityIdentifier("product-spoon").accessibilityLabel(store.t("NOMI 智能餐勺"))
                    HStack(spacing: 0) {
                        Metric(value: "\(store.todayBiteCount)", unit: "口", title: "今日已记录").accessibilityIdentifier("home-bites")
                        Rectangle().fill(Palette.line).frame(width: 1, height: 32).padding(.horizontal, 24)
                        Metric(value: store.state.hideCalories || !store.todayIntakes.contains(where: { $0.estimatedKcal != nil }) ? "—" : String(format: "%.0f", store.daily.kcal), unit: "kcal", title: "已计入 · 估算").accessibilityIdentifier("home-calories")
                    }.padding(.top, 8)
                }.padding(24).background(LinearGradient(colors: [.white, Color(white: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                PrimaryButton(title: store.activeIntegrationMealID == nil ? "开始用餐" : "继续本餐", identifier: "start-meal") { mealOpen = true }
                Button { goalOpen = true } label: {
                    Surface {
                        HStack(spacing: 22) {
                            GoalRing(fraction: progress, caption: store.state.hideCalories ? "—" : (store.settings.dailyGoal == nil ? "设定" : "\(Int(min(progress, 9.99)*100))%"))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(store.t("按自己的节奏")).font(.system(size: 17, weight: .medium))
                                Text(store.t(store.settings.dailyGoal.map { String(format: "每日目标  %.0f kcal", $0) } ?? "设定你的每日目标"))
                                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                if store.daily.pending > 0 { Text("\(store.daily.pending) " + store.t("口已记录，尚无热量估算")).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                        }
                    }
                }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("home-goal")
                HStack {
                    Text(store.t("今天的餐桌")).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button(store.t("全部记录")) { NotificationCenter.default.post(name: .openRecords, object: nil) }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                if meals.isEmpty {
                    ProductEmptyState(symbol: "fork.knife", title: "从下一餐开始", message: "吃完一口，轻按餐勺。\n把记录留给 NOMI，把注意力留给食物。")
                } else {
                    ForEach(meals.prefix(3)) { meal in MealCard(meal: meal) { path?.wrappedValue.append(AppRoute.mealDetail(meal.id)) } }
                }
                Text(store.t("只记录你的节奏，不评价你的每一餐。"))
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }.pageBackground().scrollIndicators(.hidden)
        .sheet(isPresented: $mealOpen) { NavigationStack { MealExperienceView() } }
        .sheet(isPresented: $goalOpen) { NavigationStack { DailyGoalView() } }
        .animation(.easeOut(duration: 0.25), value: store.todayBiteCount)
    }
    private var progress: Double { guard let goal = store.settings.dailyGoal else { return 0 }; return store.daily.kcal / goal }
}
extension Notification.Name { static let openRecords = Notification.Name("zhiweishao.openRecords") }
