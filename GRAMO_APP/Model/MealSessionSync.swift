import Foundation

/// A BLE write is not an armed button. Only a matching session reply confirms it.
struct MealSessionSync {
    struct Request { let id: UUID; let meal: String }
    private(set) var pending: Request?
    private(set) var confirmed: String?
    private var desired: String?
    private var sentAt = Date.distantPast
    private var confirmedAt = Date.distantPast
    private var attempts = 0

    func ready(for meal: String?) -> Bool {
        guard let meal else { return false }
        return confirmed == meal && pending == nil
    }
    mutating func next(meal: String?, now: Date, force: Bool = false) -> Request? {
        let value = meal ?? ""
        if desired != value {
            desired = value; pending = nil; confirmed = nil; attempts = 0; sentAt = .distantPast
        }
        // Frequent store saves must not replace an outstanding command ID.
        if pending != nil && now.timeIntervalSince(sentAt) < min(12, 3 * Double(max(1, attempts))) { return nil }
        if pending == nil && confirmed == value && !force && now.timeIntervalSince(confirmedAt) < 30 { return nil }
        let request = Request(id: UUID(), meal: value)
        pending = request; confirmed = nil; sentAt = now; attempts += 1
        return request
    }
    mutating func acknowledge(id: UUID, active: Bool, now: Date) -> Bool {
        guard let request = pending, request.id == id, active == !request.meal.isEmpty else { return false }
        confirmed = request.meal; confirmedAt = now; pending = nil; attempts = 0
        return true
    }
    mutating func reset() { self = Self() }
}
