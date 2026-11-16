import Foundation
import CoreBluetooth

/// Explicit extension implemented by firmware/nomi_integration; not inferred from legacy devices.
enum NomiWire {
    static let control = CBUUID(string: "6C2E0005-5B4A-4E3F-8D2C-1A0B9E8D7C6B")
    static let info = CBUUID(string: "6C2E0006-5B4A-4E3F-8D2C-1A0B9E8D7C6B")
    static let image = CBUUID(string: "6C2E0007-5B4A-4E3F-8D2C-1A0B9E8D7C6B")
    static let events = CBUUID(string: "6C2E0008-5B4A-4E3F-8D2C-1A0B9E8D7C6B")
    static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
}
struct NomiInfo: Decodable {
    var v: Int
    var `protocol`: String
    var fw: String
    var name: String
    var device: String
    var camera: Bool
    var led: Bool
    var load: Bool
    var imu: Bool
    var contact: Bool
    var button: Bool?
    var supported: Bool { v == 1 && `protocol` == "nomi1" && ["0.3.0-integration", "0.4.0-integration", "0.4.1-integration"].contains(fw) }
}
struct NomiButtonEvent: Codable {
    var v: Int
    var type: String
    var event: String
    var device: String
    var meal: String
    var at: Double // UTC epoch milliseconds, synchronized when arming a meal
    var timestamp: Date { Date(timeIntervalSince1970: at / 1000) }
    var key: String { device + ":" + event }
    var valid: Bool {
        v == 1 && type == "bite" && event.range(of: "^[0-9a-f]{16}-[0-9a-f]{8}$", options: .regularExpression) != nil &&
        device.range(of: "^[0-9A-F]{12}$", options: .regularExpression) != nil &&
        meal.hasPrefix("meal-live-") && meal.utf8.count <= 32 && at.isFinite && at >= 1_700_000_000_000 && at < 4_102_444_800_000
    }
    func belongs(to meal: Meal, now: Date) -> Bool {
        valid && meal.id == self.meal && at >= meal.startedAt && at <= now.timeIntervalSince1970 * 1000 + 2000 &&
        (meal.endedAt.map { at <= $0 } ?? (meal.status == .recording))
    }
}
struct SpoonCameraFrame {
    var id: UUID
    var data: Data
    var timestamp: Date
    var deviceID: String
}
enum NomiImageError: Error { case invalid, conflict, checksum, expired }
struct NomiImageAssembler {
    let frameID: UInt32
    let expectedCRC: UInt32
    let started: Date
    private var bytes: Data
    private var present: [Bool]
    private var received = 0
    init(frameID: UInt32, size: Int, crc: UInt32, now: Date = Date()) throws {
        guard size > 4, size <= 200_000 else { throw NomiImageError.invalid }
        self.frameID = frameID; expectedCRC = crc; started = now
        bytes = Data(repeating: 0, count: size); present = Array(repeating: false, count: size)
    }
    mutating func append(_ data: Data, now: Date = Date()) throws -> Data? {
        guard now.timeIntervalSince(started) <= 30 else { throw NomiImageError.expired }
        guard data.count > 14, data[0] == 1, data[1] == 0x20 else { throw NomiImageError.invalid }
        func u32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(data[offset+$1]) << (8*$1) } }
        guard u32(2) == frameID else { return nil } // late packets from a previous capture
        let offset = Int(u32(6)), count = data.count-14
        guard Int(u32(10)) == bytes.count, offset <= bytes.count-count else { throw NomiImageError.invalid }
        for index in 0..<count {
            let destination = offset+index, value = data[14+index]
            if present[destination] {
                guard bytes[destination] == value else { throw NomiImageError.conflict }
            } else { bytes[destination] = value; present[destination] = true; received += 1 }
        }
        guard received == bytes.count else { return nil }
        guard NomiWire.crc32(bytes) == expectedCRC, bytes.starts(with: [0xff,0xd8]), bytes.suffix(2) == Data([0xff,0xd9]) else { throw NomiImageError.checksum }
        return bytes
    }
}
