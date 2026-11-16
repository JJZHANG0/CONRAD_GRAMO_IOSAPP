import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @State private var span = 7
    @State private var selectedDate: String?
    private var days: [String] { (-(span-1)...0).map { ZWFormat.shiftDate(store.todayISO, days: $0) } }
    private var entries: [IntakeEvidence] { days.flatMap { store.intakes(on: $0) } }
    private var recordedDays: Int { days.filter { !store.intakes(on: $0).isEmpty }.count }
    private var completeDays: Int { days.filter { store.intakes(on: $0).contains { $0.estimatedKcal != nil } }.count }
    private var average: Double { entries.compactMap(\.estimatedKcal).reduce(0,+) / Double(max(completeDays,1)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ProductHeader(eyebrow: "A LITTLE EVERY DAY", title: "看见自己的节奏")
                Picker(store.t("时间范围"),selection: $span) { Text(store.t("近 7 天")).tag(7); Text(store.t("近 30 天")).tag(30) }.pickerStyle(.segmented)
                Surface {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading,spacing: 8) {
                                Text(store.t("日均已计入")).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                HStack(alignment: .firstTextBaseline,spacing: 6) {
                                    Text(store.t(store.state.hideCalories || completeDays == 0 ? "—" : String(format: "%.0f",average))).font(.system(size: 44,weight: .medium)).tracking(-2).monospacedDigit()
                                    Text(store.t("kcal")).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                                }
                            }
                            Spacer()
                            Text(store.t("\(completeDays) 天有摄入数据")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }
                        if store.state.hideCalories {
                            ProductEmptyState(symbol: "eye.slash",title: "热量已隐藏",message: "你仍然可以查看自己的记录频率。")
                        } else {
                            Chart(days,id: \.self) { day in
                                let values = store.intakes(on: day).compactMap(\.estimatedKcal)
                                if !values.isEmpty {
                                    BarMark(x: .value("日期",day), y: .value("估算热量",values.reduce(0,+)), width: .ratio(0.42))
                                        .foregroundStyle(day == store.todayISO ? Palette.ink : Color(white: 0.72)).cornerRadius(4)
                                }
                            }
                            .chartXScale(domain: days)
                            .chartXAxis { AxisMarks(values: span == 7 ? days : days.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)) { value in
                                AxisValueLabel { if let day = value.as(String.self) { Text(store.t(ZWFormat.dayNumber(day))).font(.system(size: 10)) } }
                            } }
                            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4,dash: [3,4])); AxisValueLabel().font(.system(size: 9)) } }
                            .chartYScale(domain: 0...max(100, days.map { store.intakes(on: $0).compactMap(\.estimatedKcal).reduce(0,+) }.max() ?? 0))
                            .frame(height: 170).accessibilityLabel(store.t("近\(span)天摄入趋势，仅统计有记录的日期"))
                        }
                        Text(store.t("按有摄入数据的日期计算；待完善的口次暂不计入。"))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    }
                }
                HStack(spacing: 12) {
                    Surface { Metric(value: "\(recordedDays)", unit: "天", title: "有记录的日子") }
                    Surface { Metric(value: "\(entries.count)", unit: "口", title: "累计进食记录") }
                }
                Surface {
                    VStack(alignment: .leading,spacing: 18) {
                        HStack { Image(systemName: "circle.grid.3x3.fill").font(.system(size: 15)); Text(store.t("让记录，慢慢成为习惯")).font(.system(size: 17,weight: .medium)) }
                        HStack(spacing: 7) {
                            ForEach(Array(days.suffix(7)),id: \.self) { day in
                                VStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(store.intakes(on: day).isEmpty ? Palette.background : Palette.ink).frame(height: 31)
                                        if !store.intakes(on: day).isEmpty { Image(systemName: "checkmark").font(.system(size: 10,weight: .bold)).foregroundStyle(.white) }
                                    }
                                    Text(store.t((store.language == .zh ? L10n.weekdayZH(day) : L10n.weekday(day, chip: true)))).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                        Text(store.t(recordedDays == 0 ? "不用等一个完美的开始。从今天的一餐，留下第一条记录。" : "你已经留下了\(recordedDays)天的日常。持续记录，比单次数字更值得回看。"))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    }
                }
            }.padding(.horizontal,22).padding(.bottom,28)
        }.pageBackground().scrollIndicators(.hidden)
    }
}
