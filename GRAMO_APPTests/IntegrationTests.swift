import XCTest
import UIKit
@testable import GRAMO_APP

final class IntegrationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    @MainActor
    func testForegroundDayRefreshMovesHeaderWithLedger() {
        let domain = "nomi.day.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = AppStore(defaults: defaults)
        store.refreshDay(now: now)
        XCTAssertEqual(store.todayISO, ZWFormat.formatISODate(now))
        let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now)!
        store.refreshDay(now: tomorrow)
        XCTAssertEqual(store.todayISO, ZWFormat.formatISODate(tomorrow))
        XCTAssertEqual(store.daily, IntakeLedger.day(store.state.meals, now: tomorrow))
    }
    func evidence(_ id: String = "event-1") -> IntakeEvidence {
        IntakeEvidence(eventID: id, deviceID: "replay-fixture", timestamp: now,
                       dish: FoodCandidate(id: "50", name: "番茄炒蛋", rawLabel: "Scrambled egg with tomato", confidence: nil,
                                           source: "测试夹具（非营养数据库）", modelVersion: "test", imageID: nil, region: nil),
                       grams: 10, kcalPer100g: 100, nutritionSource: "测试数值，仅验证算术", measurement: "回放", confirmedEating: true, corrected: false, note: "synthetic")
    }
    func state() -> AppState {
        var state = Logic.createInitial(now)
        state = Logic.applyStartMeal(state, now: now.timeIntervalSince1970*1000).state
        return state
    }
    func testDuplicateIsOneBiteAndFinishDoesNotDoubleCount() {
        var s = state(); let id = s.recordingMealId
        s = IntakeLedger.upsert(evidence(), mealID: id, in: s)
        s = IntakeLedger.upsert(evidence(), mealID: id, in: s)
        XCTAssertEqual(s.meals[0].foods.count, 1)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).kcal, 10)
        s = Logic.applyEndMeal(s, mealId: id, now: now.timeIntervalSince1970*1000+1000)
        s = Logic.applyFinishMeal(s, mealId: id, now: now.timeIntervalSince1970*1000+2000)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).kcal, 10)
        XCTAssertEqual(s.meals[0].foods.count, 1)
    }
    func testMissingIsNotZeroAndManualDishCorrectionRecalculates() {
        var e = evidence(); e.grams = nil; XCTAssertNil(e.food.kcal)
        e.grams = 10; e.dish = nil; XCTAssertNil(e.food.kcal)
        e.dish = evidence().dish; e.nutritionSource = ""; XCTAssertNil(e.food.kcal)
        e = evidence(); var s = state(); let id = s.recordingMealId
        s = IntakeLedger.upsert(e, mealID: id, in: s)
        e.dish?.name = "改为豆腐"; e.kcalPer100g = 80; e.corrected = true
        s = IntakeLedger.upsert(e, mealID: id, in: s, correction: true)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).kcal, 8)
        XCTAssertEqual(s.meals[0].foods[0].name, "改为豆腐")
        e.grams = nil; s = IntakeLedger.upsert(e, mealID: id, in: s, correction: true)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).pending, 1)
        XCTAssertNil(s.meals[0].foods[0].kcal)
    }
    func testThresholdEqualityCorrectionAndDeletion() {
        var s = state(); let id = s.recordingMealId; var e = evidence()
        s = IntakeLedger.upsert(e, mealID: id, in: s)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).color(goal: 10), .red)
        e.grams = 9; s = IntakeLedger.upsert(e, mealID: id, in: s, correction: true)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: now).color(goal: 10), .green)
        s.integration = IntegrationSettings(deletedEventKeys: [e.key]); s.meals[0].foods = []
        s = IntakeLedger.upsert(e, mealID: id, in: s)
        XCTAssertTrue(s.meals[0].foods.isEmpty)
        XCTAssertNil(DailyIntake().color(goal: 0)); XCTAssertNil(DailyIntake().color(goal: .nan))
    }
    func testCrossMidnightUsesEventTimeAndLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8*3600)!
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(86400)
        var a = evidence("before"); a.timestamp = midnight.addingTimeInterval(-1)
        var b = evidence("after"); b.timestamp = midnight.addingTimeInterval(1)
        var s = state(); let id = s.recordingMealId
        s = IntakeLedger.upsert(a, mealID: id, in: s); s = IntakeLedger.upsert(b, mealID: id, in: s)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: midnight.addingTimeInterval(-1), calendar: calendar).kcal, 10)
        XCTAssertEqual(IntakeLedger.day(s.meals, now: midnight.addingTimeInterval(2), calendar: calendar).kcal, 10)
    }
    func testEmptySpoonAndNonEatingDoNotProduceCalories() {
        var e = evidence(); e.grams = 0; XCTAssertNil(e.estimatedKcal)
        e.grams = -2; XCTAssertNil(e.estimatedKcal)
        e.grams = .nan; XCTAssertNil(e.estimatedKcal)
        e.grams = 20; e.confirmedEating = false; XCTAssertNil(e.estimatedKcal)
        var machine = EatingEventMachine()
        machine.advance(time: 1, loadedStable: true); machine.advance(time: 2, lifted: true)
        machine.advance(time: 3, abnormal: true)
        XCTAssertEqual(machine.phase, .pending)
        machine.advance(time: 4, confirmedEating: true, grams: 10)
        XCTAssertEqual(machine.phase, .pending)
    }
    func testLoadNeedsComparableStableCalibratedWindows() {
        let cal = LoadCalibration(head: .spoon, tare: 100, rawUnitsPerGram: 10, referenceGrams: 20, verified: true)
        let before = (0..<6).map { LoadSample(time: Double($0)*0.1, raw: 250, pitch: 0, roll: 0) }
        var after = (0..<6).map { LoadSample(time: 2+Double($0)*0.1, raw: 150, pitch: 0, roll: 0) }
        XCTAssertEqual(PortionEstimator.load(before: before, after: after, calibration: cal, head: .spoon), 10)
        XCTAssertNil(PortionEstimator.load(before: before, after: after, calibration: cal, head: .fork))
        after[0].pitch = 20
        XCTAssertNil(PortionEstimator.load(before: before, after: after, calibration: cal, head: .spoon))
        XCTAssertNil(PortionEstimator.visual(coverage: 0.5, points: [], head: .spoon, calibratedView: true))
        XCTAssertNil(PortionEstimator.visual(coverage: 0.5, points: [(0,0),(0.5,10),(1,20)], head: .fork, calibratedView: true))
        XCTAssertEqual(PortionEstimator.visual(coverage: 0.75, points: [(0,0),(0.5,10),(1,20)], head: .spoon, calibratedView: true),15)
    }
    func testKnownPacketReadinessAndFrameValidation() {
        let s = Logic.createInitial(now)
        XCTAssertFalse(Logic.applySpoonPacket(s, .ignored(type: 127), now: 0).device.spoonLinked)
        var buffer = SpoonFrameBuffer()
        let valid = Data([1,4,0,0,0,0,1,0,82,86])
        XCTAssertTrue(buffer.append(Data(valid.prefix(4)), now: now).isEmpty)
        XCTAssertEqual(buffer.append(Data(valid.dropFirst(4)), now: now), [.battery(percent: 82)])
        XCTAssertEqual(buffer.append(valid+valid, now: now).count, 2)
        _ = buffer.append(Data(valid.prefix(4)), now: now)
        XCTAssertTrue(buffer.append(Data(valid.dropFirst(4)), now: now.addingTimeInterval(3)).isEmpty)
        XCTAssertEqual(buffer.append(valid, now: now.addingTimeInterval(4)).count, 1)
        var bad = valid; bad[0] = 2; XCTAssertTrue(buffer.append(bad).isEmpty)
        bad = valid; bad[9] ^= 1; XCTAssertTrue(buffer.append(bad).isEmpty)
        bad = valid; bad[6] = 255; XCTAssertTrue(buffer.append(bad).isEmpty)
        XCTAssertEqual(buffer.append(valid).count, 1)
    }
    func testMealIDsAreScopedAndDeletedMealCannotReturn() {
        var s = state()
        s = Logic.applySpoonPacket(s, .mealStart(id: 7, time: now), now: 0, deviceID: "a")
        s = Logic.applySpoonPacket(s, .mealStart(id: 7, time: now), now: 0, deviceID: "b")
        XCTAssertEqual(s.meals.count, 3)
        s = Logic.clearMeals(s)
        s = Logic.applySpoonPacket(s, .mealStart(id: 7, time: now), now: 0, deviceID: "a")
        XCTAssertTrue(s.meals.isEmpty)
    }
    func testOldJSONDecodesAndNewEvidencePersists() throws {
        let original = state()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String:Any])
        json.removeValue(forKey: "integration")
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.meals, original.meals)
        var s = IntakeLedger.upsert(evidence(), mealID: original.recordingMealId, in: original)
        s.integration = IntegrationSettings(dailyGoal: 10)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(s)), s)
    }
    func testFreshInstallAndFinishedEmptyMealStayEmpty() {
        XCTAssertTrue(Logic.createInitial(now).meals.isEmpty)
        var s = state(); let id = s.recordingMealId
        s = Logic.applyEndMeal(s, mealId: id, now: 100)
        s = Logic.applyFinishMeal(s, mealId: id, now: 200)
        XCTAssertTrue(s.meals[0].foods.isEmpty); XCTAssertNil(s.meals[0].biteCount)
    }
    @MainActor func testLEDOnlyChangesOnTransitionReconnectOrExplicitSyncAndACK() {
        final class Transport: LEDTransport {
            var sent: [(GoalColor,UUID)] = []
            func send(color: GoalColor, commandID: UUID) throws { sent.append((color,commandID)) }
        }
        let transport = Transport(); var led = LEDSync()
        led.update(color: .green, connected: true, transport: transport)
        XCTAssertEqual(transport.sent.count,1)
        led.update(color: .green, connected: true, transport: transport)
        XCTAssertEqual(transport.sent.count,1)
        led.acknowledge(UUID(), applied: .green)
        XCTAssertEqual(led.status, .pending(transport.sent[0].1))
        led.acknowledge(transport.sent[0].1, applied: .green); XCTAssertEqual(led.status,.applied(.green))
        led.update(color: .red, connected: true, transport: transport); XCTAssertEqual(transport.sent.count,2)
        led.update(color: .red, connected: false, transport: transport)
        led.update(color: .red, connected: true, transport: transport); XCTAssertEqual(transport.sent.count,3)
        led.update(color: .green, connected: true, transport: transport); XCTAssertEqual(transport.sent.count,4)
        led.resync(); led.update(color: .green, connected: true, transport: transport); XCTAssertEqual(transport.sent.count,5)
        led.update(color: .green, connected: true, transport: nil); XCTAssertEqual(led.status,.unsupported)
    }
}

final class ImagePreprocessingTests: XCTestCase {
    func testBicubicMatchesPillowRGBFixture() throws {
        let bundle = Bundle(for: Self.self)
        let input = try XCTUnwrap(bundle.url(forResource: "interpolation-input", withExtension: "png"))
        let golden = try XCTUnwrap(bundle.url(forResource: "interpolation-expected", withExtension: "png"))
        let source = try XCTUnwrap(UIImage(contentsOfFile: input.path)?.cgImage)
        let expected = try XCTUnwrap(UIImage(contentsOfFile: golden.path)?.cgImage)
        let actual = try FoodImagePreprocessor.resize(source, width: 342, height: 256)
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width*image.height*4)
            data.withUnsafeMutableBytes { ptr in
                let context = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.draw(image,in: CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            return data
        }
        let a = pixels(actual), e = pixels(expected)
        let differences = a.indices.filter { $0%4 != 3 }.map { abs(Int(a[$0])-Int(e[$0])) }
        XCTAssertLessThanOrEqual(differences.max()!, 1)
        XCTAssertLessThan(Double(differences.reduce(0,+))/Double(differences.count), 0.01)
    }
}

final class ReplayFixtureTests: XCTestCase {
    func testDocumentedReplayIsNotADeviceOrCalorieSource() throws {
        struct Replay: Decodable {
            struct Message: Decodable { var channel: String; var hex: String }
            var origin: String
            var device_id: String
            var messages: [Message]
            var expected_meals: Int
            var expected_positive_bites: Int
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "spoon-v1-replay", withExtension: "json"))
        let replay = try JSONDecoder().decode(Replay.self, from: Data(contentsOf: url))
        XCTAssertTrue(replay.origin.contains("NOT hardware"))
        var state = Logic.createInitial(Date())
        var buffers: [String: SpoonFrameBuffer] = [:]
        for message in replay.messages {
            let characters = Array(message.hex)
            let bytes = stride(from: 0, to: characters.count, by: 2).map { UInt8(String(characters[$0...($0+1)]), radix: 16)! }
            var buffer = buffers[message.channel] ?? SpoonFrameBuffer()
            for packet in buffer.append(Data(bytes)) {
                state = Logic.applySpoonPacket(state, packet, now: 0, deviceID: replay.device_id)
            }
            buffers[message.channel] = buffer
        }
        XCTAssertEqual(state.meals.count, replay.expected_meals)
        XCTAssertEqual(state.meals.first?.biteCount ?? 0, replay.expected_positive_bites)
        XCTAssertNil(state.meals.first.flatMap(Logic.mealKcal))
    }
}
