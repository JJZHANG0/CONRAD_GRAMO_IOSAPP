import SwiftUI

struct RecordsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.navPath) private var path
    @State private var selected = ""
    @State private var editing = false
    @State private var showCalendar = false
    private var day: String { selected.isEmpty ? store.todayISO : selected }
    private var meals: [Meal] { store.state.meals.filter { meal in meal.date == day || meal.foods.contains { $0.evidence.map { ZWFormat.formatISODate($0.timestamp) == day } == true } }.sorted { $0.startedAt > $1.startedAt } }
    private var dates: [String] { (-6...0).map { ZWFormat.shiftDate(day, days: $0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    ProductHeader(eyebrow: "YOUR TABLE", title: "好好吃饭的日子")
                    Spacer()
                    Button { showCalendar.toggle() } label: { Image(systemName: "calendar").font(.system(size: 20)).frame(width: 44,height: 44) }
                        .accessibilityLabel(store.t("选择日期")).accessibilityIdentifier("records-calendar")
                }
                HStack {
                    Button { selected = ZWFormat.shiftDate(day, days: -7) } label: { Image(systemName: "chevron.left").frame(width: 36,height: 36) }.accessibilityLabel(store.t("上一周"))
                    Spacer()
                    Text(store.t(L10n.dateLine(day, week: false, store.language))).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button { selected = min(ZWFormat.shiftDate(day, days: 7), store.todayISO) } label: { Image(systemName: "chevron.right").frame(width: 36,height: 36) }.disabled(day == store.todayISO).accessibilityLabel(store.t("下一周"))
                }.padding(.bottom, -16)
                HStack(spacing: 5) {
                    ForEach(dates,id: \.self) { date in
                        Button { selected = date } label: {
                            VStack(spacing: 10) {
                                Text(store.t((store.language == .zh ? L10n.weekdayZH(date) : L10n.weekday(date, chip: true)))).font(.system(size: 11))
                                Text(store.t(ZWFormat.dayNumber(date))).font(.system(size: 17, weight: .medium)).monospacedDigit()
                                Circle().fill(store.state.meals.contains { $0.date == date } ? (date == day ? Color.white : Palette.ink) : Color.clear).frame(width: 3,height: 3)
                            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(date == day ? .white : Palette.ink)
                                .background(date == day ? Palette.ink : .clear, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(ProductPressStyle()).accessibilityLabel(store.t("\(date)的记录"))
                    }
                }
                Surface(dark: true) {
                    HStack {
                        Metric(value: "\(store.intakes(on: day).count)", unit: "口", title: "进食记录", dark: true)
                        Metric(value: store.state.hideCalories ? "—" : (meals.isEmpty ? "—" : String(format: "%.0f", summary.kcal)), unit: "kcal", title: "已计入 · 估算", dark: true)
                        Metric(value: "\(meals.count)", unit: "餐", title: "留下的日常", dark: true)
                    }
                }.accessibilityIdentifier("records-summary")
                HStack {
                    Text(store.t(day == store.todayISO ? "今日餐次" : "餐次记录")).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button { path?.wrappedValue.append(AppRoute.addEntry(mealId: "", date: day)) } label: { Label(store.t("补记"),systemImage: "plus").font(.system(size: 13, weight: .medium)) }.accessibilityIdentifier("records-add")
                }
                if meals.isEmpty {
                    ProductEmptyState(symbol: "book.closed", title: "这一页，留给下一餐", message: "还没有留下记录。\n没有记录的日子，不会被算作零摄入。")
                } else {
                    ForEach(meals) { meal in MealCard(meal: meal) { path?.wrappedValue.append(AppRoute.mealDetail(meal.id)) } }
                    if summary.pending > 0 { Text(store.t("\(summary.pending) 口 / 项待完善，补充后会自动更新累计。")).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                }
            }.padding(.horizontal,22).padding(.bottom,28)
        }.pageBackground().scrollIndicators(.hidden)
        .sheet(isPresented: $showCalendar) {
            VStack(spacing: 20) {
                Text(store.t("回看某一天")).font(.headline)
                DatePicker(store.t("日期"), selection: Binding(get: { ZWFormat.parseISODate(day) }, set: { selected = ZWFormat.formatISODate($0) }), in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical)
                PrimaryButton(title: "查看记录") { showCalendar = false }
            }.padding(24).presentationDetents([.medium,.large])
        }
    }
    private var summary: DailyIntake { IntakeLedger.day(store.state.meals, now: ZWFormat.parseISODate(day)) }
}
