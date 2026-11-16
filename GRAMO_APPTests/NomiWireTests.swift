import XCTest
@testable import GRAMO_APP

final class NomiWireTests: XCTestCase {
    let jpeg = Data([0xff,0xd8,1,2,3,4,5,6,0xff,0xd9])
    func packet(offset: Int, payload: Data, frame: UInt32 = 7, total: UInt32 = 10) -> Data {
        var out = Data([1,0x20])
        for value in [frame,UInt32(offset),total] { for shift in 0..<4 { out.append(UInt8(truncatingIfNeeded: value >> (8*shift))) } }
        out.append(payload); return out
    }
    func testCRCAndOutOfOrderDuplicateFrameChunks() throws {
        XCTAssertEqual(NomiWire.crc32(Data("123456789".utf8)),0xcbf43926)
        var stream = try NomiImageAssembler(frameID: 7,size: jpeg.count,crc: NomiWire.crc32(jpeg))
        let tail = packet(offset: 5,payload: jpeg.suffix(5))
        XCTAssertNil(try stream.append(tail)); XCTAssertNil(try stream.append(tail))
        XCTAssertNil(try stream.append(packet(offset: 0,payload: jpeg.prefix(5),frame: 6)))
        XCTAssertEqual(try stream.append(packet(offset: 0,payload: jpeg.prefix(5))),jpeg)
    }
    func testBadSizesConflictsChecksumAndTimeoutAreRejected() throws {
        XCTAssertThrowsError(try NomiImageAssembler(frameID: 1,size: 200001,crc: 0))
        var stream = try NomiImageAssembler(frameID: 7,size: jpeg.count,crc: 0)
        XCTAssertThrowsError(try stream.append(packet(offset: 0,payload: jpeg)))
        stream = try NomiImageAssembler(frameID: 7,size: jpeg.count,crc: 0)
        XCTAssertNil(try stream.append(packet(offset: 0,payload: jpeg.prefix(5))))
        XCTAssertThrowsError(try stream.append(packet(offset: 0,payload: Data([1,2,3]))))
        stream = try NomiImageAssembler(frameID: 7,size: jpeg.count,crc: 0)
        XCTAssertThrowsError(try stream.append(packet(offset: 9,payload: Data([1,2,3]))))
        stream = try NomiImageAssembler(frameID: 7,size: jpeg.count,crc: 0,now: Date(timeIntervalSince1970: 0))
        XCTAssertThrowsError(try stream.append(packet(offset: 0,payload: jpeg),now: Date(timeIntervalSince1970: 31)))
    }
    func testCapabilityVersionAndUInt32JSONDecoding() throws {
        let info = Data(#"{"v":1,"protocol":"nomi1","fw":"0.3.0-integration","name":"NOMI01","device":"test","camera":true,"led":true,"load":false,"imu":false,"contact":false}"#.utf8)
        let parsed = try JSONDecoder().decode(NomiInfo.self,from: info)
        XCTAssertTrue(parsed.supported); XCTAssertFalse(parsed.load)
        let metadata = try JSONSerialization.jsonObject(with: Data(#"{"crc":4294967295,"frame":7}"#.utf8)) as! [String:Any]
        XCTAssertEqual(metadata["crc"] as? UInt32,UInt32.max)
    }
}
