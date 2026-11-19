import Foundation

/// A classifier suggestion, not proof of food, ingestion, quantity or nutrition.
struct DishObservation {
    var frameID: UUID
    var timestamp: Date
    var deviceID: String
    var mealID: String
    var candidates: [FoodCandidate]
}

enum AutomaticDish {
    // Provisional consistency gates, not calibrated food/non-food rejection thresholds.
    static let maximumAge: TimeInterval = 12
    static func suggestion(in observations: [DishObservation], device: String, meal: String, at time: Date) -> FoodCandidate? {
        let nearby = observations.filter {
            $0.deviceID == device && $0.mealID == meal && $0.timestamp <= time && time.timeIntervalSince($0.timestamp) <= maximumAge
        }.sorted { $0.timestamp < $1.timestamp }
        guard nearby.count >= 2 else { return nil }
        // A blurred/empty last view after eating must not replace the recent plate.
        // Retain the latest consistent pair briefly, unless a later confident view
        // suggests a different dish. This is context carryover, not mouth detection.
        for index in stride(from: nearby.count - 1, through: 1, by: -1) {
            let a = nearby[index - 1], b = nearby[index]
            guard a.frameID != b.frameID, a.timestamp < b.timestamp,
                  let first = confidentTop(a.candidates), let last = confidentTop(b.candidates),
                  first.classID == last.classID else { continue }
            let changed = nearby.dropFirst(index + 1).contains {
                if let newer = confidentTop($0.candidates) { return newer.classID != last.classID }
                return false
            }
            return changed ? nil : last
        }
        return nil
    }
    private static func confidentTop(_ candidates: [FoodCandidate]) -> FoodCandidate? {
        guard candidates.count >= 2, let top = candidates.first, let id = top.classID, !id.isEmpty,
              let confidence = top.confidence, let runnerUp = candidates[1].confidence,
              confidence.isFinite, runnerUp.isFinite, (0...1).contains(confidence), (0...1).contains(runnerUp),
              confidence >= 0.6, confidence - runnerUp >= 0.2 else { return nil }
        return top
    }
}
