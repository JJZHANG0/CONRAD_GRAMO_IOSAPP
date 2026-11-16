import SwiftUI

struct ProductHeader: View {
    @Environment(AppStore.self) private var store
    var eyebrow: String
    var title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(eyebrow.uppercased())).font(.system(size: 11, weight: .semibold)).tracking(2.4).foregroundStyle(Palette.secondary)
            Text(store.t(title)).font(.system(size: 32, weight: .semibold)).tracking(-1).foregroundStyle(Palette.ink)
        }.padding(.top, 12)
    }
}
struct Surface<Content: View>: View {
    var dark = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Palette.ink : Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(dark ? Color.clear : Color.black.opacity(0.025)))
    }
}
struct Metric: View {
    @Environment(AppStore.self) private var store
    var value: String
    var unit: String
    var title: String
    var dark = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(store.t(value)).font(.system(size: 30, weight: .medium)).tracking(-1).monospacedDigit().contentTransition(.numericText())
                Text(store.t(unit)).font(.system(size: 11, weight: .medium)).opacity(0.55)
            }
            Text(store.t(title)).font(.system(size: 12)).opacity(0.6)
        }.foregroundStyle(dark ? Color.white : Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct GoalRing: View {
    @Environment(AppStore.self) private var store
    var fraction: Double
    var caption: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.06), lineWidth: 6)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(store.t(caption)).font(.system(size: 15, weight: .medium)).monospacedDigit().minimumScaleFactor(0.7).padding(12)
        }.frame(width: 74, height: 74).accessibilityElement(children: .ignore).accessibilityLabel(store.t("目标进度 \(caption)"))
    }
}
struct ProductEmptyState: View {
    @Environment(AppStore.self) private var store
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .ultraLight)).padding(.bottom, 4)
            Text(store.t(title)).font(.system(size: 18, weight: .medium))
            Text(store.t(message)).font(.system(size: 14)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}
struct ProductPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
struct MealCard: View {
    let meal: Meal
    @Environment(AppStore.self) private var store
    var action: () -> Void
    private var entries: [IntakeEvidence] { meal.foods.compactMap(\.evidence) }
    private var total: Double { entries.compactMap(\.estimatedKcal).reduce(0,+) }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(Palette.background).frame(width: 50, height: 58)
                    Image(systemName: meal.name.contains("早") ? "sunrise" : "fork.knife").font(.system(size: 21, weight: .light))
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.t(meal.name)).font(.system(size: 17, weight: .medium))
                    Text(store.t("\(meal.time) · \(meal.status == .recording ? "用餐中" : "\(entries.count) 口已记录")"))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(store.t(store.state.hideCalories ? "已隐藏" : (entries.contains { $0.estimatedKcal != nil } ? String(format: "%.0f", total) : "待完善")))
                        .font(.system(size: 20, weight: .medium)).monospacedDigit()
                    Text(store.t(entries.contains { $0.estimatedKcal != nil } && !store.state.hideCalories ? "kcal · 估算" : "份量与菜品"))
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(ProductPressStyle()).accessibilityIdentifier("meal-\(meal.id)")
    }
}

/// Sheets cover RootView's banner, so each consumer sheet carries its own context.
private struct SimulationContext: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top,spacing: 0) {
            #if DEBUG
            if store.isSimulation {
                Text(store.t("模拟设备 · 独立演示数据")).font(.system(size: 10,weight: .medium)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical,6).background(Palette.background)
                    .accessibilityIdentifier("simulation-context")
            }
            #endif
        }
    }
}
extension View { func simulationContext() -> some View { modifier(SimulationContext()) } }
