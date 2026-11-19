import Foundation

struct FoodCandidate: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var rawLabel: String
    var confidence: Double?
    var source: String
    var modelVersion: String
    var imageID: String?
    var classID: String? = nil
    var region: [Double]? // normalized x, y, width, height in orientation-corrected image
}

struct IntakeEvidence: Codable, Equatable {
    var eventID: String
    var deviceID: String
    var timestamp: Date
    var dish: FoodCandidate?
    var grams: Double?
    var kcalPer100g: Double?
    var nutritionSource: String
    var measurement: String
    var confirmedEating: Bool
    var corrected: Bool
    var note: String
    var frames: [IntakeFrame]? = nil
    var automaticDish: Bool? = nil // Provisional image classification; never a manual confirmation.
    var estimatedKcal: Double? {
        guard confirmedEating, let dish, !dish.name.isEmpty,
              let grams, grams.isFinite, grams > 0,
              let density = kcalPer100g, density.isFinite, density > 0,
              !nutritionSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return grams * density / 100
    }
    var key: String { deviceID + ":" + eventID }
    var food: FoodItem {
        FoodItem(id: key, name: dish?.name ?? "菜品待确认",
                 portion: grams.map { String(format: "约 %.1f g · %@", $0, measurement) } ?? "重量待确认",
                 kcal: estimatedKcal.map { Int($0.rounded()) }, source: deviceID == "manual" ? .manual : .utensil,
                 check: nil, evidence: self)
    }
}
struct IntakeFrame: Codable, Equatable, Identifiable {
    var id: String
    var timestamp: Date
    var relativePath: String
    var phase: String // nearby before/after; never claims visibility or actual ingestion
}

struct IntegrationSettings: Codable, Equatable {
    var dailyGoal: Double?
    var candidates: [FoodCandidate] = []
    var currentDishID: String?
    var mealID: String?
    var deletedEventKeys: [String] = []
    var deviceAliases: [String: String]?
    var currentDishSince: Date?
}

enum GoalColor: String, Codable { case green, red }
struct DailyIntake: Equatable {
    var kcal: Double = 0
    var pending: Int = 0
    var legacyItems: Int = 0
    func color(goal: Double?) -> GoalColor? {
        guard let goal, goal.isFinite, goal > 0 else { return nil }
        return kcal >= goal ? .red : .green
    }
}

enum IntakeLedger {
    static func day(_ meals: [Meal], now: Date, calendar: Calendar = .autoupdatingCurrent) -> DailyIntake {
        var result = DailyIntake()
        var seen = Set<String>()
        for meal in meals {
            for food in meal.foods {
                if let e = food.evidence {
                    guard calendar.isDate(e.timestamp, inSameDayAs: now), seen.insert(e.key).inserted else { continue }
                    if let kcal = e.estimatedKcal { result.kcal += kcal } else { result.pending += 1 }
                } else if meal.date == ZWFormat.formatISODate(now) {
                    // Preserve old records but never use untraceable demo/legacy estimates to drive hardware.
                    result.legacyItems += 1
                    result.pending += 1
                }
            }
        }
        return result
    }

    static func upsert(_ evidence: IntakeEvidence, mealID: String, in state: AppState, correction: Bool = false) -> AppState {
        guard !(state.integration?.deletedEventKeys.contains(evidence.key) ?? false),
              let index = state.meals.firstIndex(where: { $0.id == mealID }) else { return state }
        var next = state
        for mi in next.meals.indices {
            if let fi = next.meals[mi].foods.firstIndex(where: { $0.evidence?.key == evidence.key }) {
                guard correction else { return state }
                next.meals[mi].foods[fi] = evidence.food
                next.meals[mi].updatedAt = Date().timeIntervalSince1970 * 1000
                next.meals[mi].briefCount = -1
                return next
            }
        }
        next.meals[index].foods.append(evidence.food)
        next.meals[index].briefCount = -1
        next.meals[index].updatedAt = Date().timeIntervalSince1970 * 1000
        return next
    }
}

// A hardware adapter may feed these only once units, head identity and timing are verified.
struct LoadCalibration: Codable, Equatable {
    var head: UtensilHead
    var tare: Double
    var rawUnitsPerGram: Double
    var referenceGrams: Double
    var verified: Bool
}
struct LoadSample: Equatable {
    var time: TimeInterval
    var raw: Double
    var pitch: Double
    var roll: Double
}
enum PortionEstimator {
    static func load(before: [LoadSample], after: [LoadSample], calibration: LoadCalibration, head: UtensilHead) -> Double? {
        guard calibration.verified, calibration.head == head, head != .none,
              calibration.referenceGrams.isFinite, calibration.referenceGrams > 0,
              calibration.tare.isFinite, calibration.rawUnitsPerGram.isFinite,
              abs(calibration.rawUnitsPerGram) > 0.000001,
              let a = stable(before, calibration), let b = stable(after, calibration),
              let last = before.last, let first = after.first, last.time < first.time,
              first.time - last.time < 30,
              abs(a.pitch - b.pitch) <= 5, abs(a.roll - b.roll) <= 5 else { return nil }
        let grams = a.grams - b.grams
        return grams > 0 && grams <= 80 && b.grams >= -1 ? grams : nil
    }
    private static func stable(_ samples: [LoadSample], _ c: LoadCalibration) -> (grams: Double, pitch: Double, roll: Double)? {
        guard samples.count >= 5, let first = samples.first, let last = samples.last,
              last.time - first.time >= 0.5, last.time - first.time <= 3,
              zip(samples, samples.dropFirst()).allSatisfy({ $0.time < $1.time }),
              samples.allSatisfy({ $0.raw.isFinite && $0.time.isFinite && $0.pitch.isFinite && $0.roll.isFinite }) else { return nil }
        let weights = samples.map { ($0.raw - c.tare) / c.rawUnitsPerGram }
        guard weights.max()! - weights.min()! <= 1,
              samples.map(\.pitch).max()! - samples.map(\.pitch).min()! <= 3,
              samples.map(\.roll).max()! - samples.map(\.roll).min()! <= 3 else { return nil }
        let n = Double(samples.count)
        return (weights.reduce(0,+)/n, samples.map(\.pitch).reduce(0,+)/n, samples.map(\.roll).reduce(0,+)/n)
    }
    // Calibrated points belong to a single head, food group and fixed/rectified camera view.
    static func visual(coverage: Double, points: [(coverage: Double, grams: Double)], head: UtensilHead,
                       calibratedView: Bool) -> Double? {
        guard head == .spoon, calibratedView, coverage.isFinite, (0...1).contains(coverage), points.count >= 3,
              points.allSatisfy({ $0.coverage.isFinite && (0...1).contains($0.coverage) && $0.grams.isFinite && $0.grams >= 0 }),
              zip(points, points.dropFirst()).allSatisfy({ $0.coverage < $1.coverage && $0.grams <= $1.grams }) else { return nil }
        for (a,b) in zip(points, points.dropFirst()) where coverage >= a.coverage && coverage <= b.coverage {
            return a.grams + (coverage-a.coverage)/(b.coverage-a.coverage)*(b.grams-a.grams)
        }
        return nil // never extrapolate an uncalibrated loading
    }
}

enum EatingPhase: String { case idle, loaded, lifted, contactCandidate, postStable, settled, pending }
struct EatingEventMachine {
    private(set) var phase: EatingPhase = .idle
    private var start: TimeInterval?
    mutating func advance(time: TimeInterval, loadedStable: Bool = false, lifted: Bool = false,
                          contact: Bool = false, afterStable: Bool = false,
                          confirmedEating: Bool = false, abnormal: Bool = false, grams: Double? = nil) {
        guard time.isFinite else { phase = .pending; return }
        if let start, time < start || time-start > 30 { phase = .pending; return }
        if abnormal { phase = .pending; return }
        switch phase {
        case .idle: if loadedStable { phase = .loaded; start = time }
        case .loaded: if lifted { phase = .lifted }
        case .lifted: if contact { phase = .contactCandidate }
        case .contactCandidate: if afterStable { phase = .postStable }
        case .postStable:
            if confirmedEating, let grams, grams.isFinite, grams > 0, grams <= 80 { phase = .settled }
            else { phase = .pending }
        default: break
        }
    }
}

// Nomi's verified extension implements this; unsupported devices keep a nil transport.
@MainActor protocol LEDTransport: AnyObject {
    func send(color: GoalColor, commandID: UUID) throws
}
@MainActor struct LEDSync {
    enum Status: Equatable { case unsupported, unset, disconnected, pending(UUID), applied(GoalColor), failed }
    private(set) var status: Status = .unsupported
    private var desired: GoalColor?
    private var sent: GoalColor?
    private var connected = false
    private var lastSentAt: Date?
    mutating func update(color: GoalColor?, connected: Bool, transport: LEDTransport?, now: Date = Date()) {
        let reconnect = connected && !self.connected
        self.connected = connected
        desired = color
        guard let color else { sent = nil; status = .unset; return }
        guard connected else { sent = nil; status = .disconnected; return }
        guard let transport else { sent = nil; status = .unsupported; return }
        if case .pending = status, let lastSentAt, now.timeIntervalSince(lastSentAt) > 8 { status = .failed }
        guard reconnect || color != sent else { return }
        let id = UUID()
        do { try transport.send(color: color, commandID: id); sent = color; lastSentAt = now; status = .pending(id) }
        catch { status = .failed; sent = color }
    }
    mutating func acknowledge(_ id: UUID, applied: GoalColor) {
        guard status == .pending(id), applied == desired else { return }
        status = .applied(applied)
    }
    mutating func resync() { sent = nil }
}
