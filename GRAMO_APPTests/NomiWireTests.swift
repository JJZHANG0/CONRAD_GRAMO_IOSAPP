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
    func testFastPreviewRequiresKnownFirmwareAndPreservesLegacySupport() throws {
        let json = #"{"v":1,"protocol":"nomi1","fw":"0.4.3-integration","name":"NOMI01","device":"test","camera":true,"led":true,"load":false,"imu":false,"contact":false}"#
        var info = try JSONDecoder().decode(NomiInfo.self, from: Data(json.utf8))
        XCTAssertTrue(info.supported); XCTAssertTrue(info.fastPreview)
        info.fw = "0.4.2-integration"; XCTAssertTrue(info.supported); XCTAssertFalse(info.fastPreview)
        info.fw = "unknown"; XCTAssertFalse(info.supported); XCTAssertFalse(info.fastPreview)
    }
    func testCaptureTimeDoesNotPretendTransferCompletionIsExposureTime() throws {
        let start = Date(timeIntervalSince1970: 100), header = start.addingTimeInterval(0.1)
        XCTAssertEqual(try NomiCameraTiming.capturedAt(requestedAt: start, metadataReceivedAt: header, ageMilliseconds: nil), start)
        XCTAssertEqual(try NomiCameraTiming.capturedAt(requestedAt: start, metadataReceivedAt: header, ageMilliseconds: 300), header.addingTimeInterval(-0.3))
        for age in [-1.0, 10001, .nan, .infinity] {
            XCTAssertThrowsError(try NomiCameraTiming.capturedAt(requestedAt: start, metadataReceivedAt: header, ageMilliseconds: age))
        }
    }
    func testLargerNegotiatedPacketsAllowReorderingAndRetryWithoutCorruption() throws {
        var bytes = Data([0xff,0xd8]); bytes.append(Data((0..<800).map { UInt8($0 % 251) })); bytes.append(contentsOf: [0xff,0xd9])
        var stream = try NomiImageAssembler(frameID: 7, size: bytes.count, crc: NomiWire.crc32(bytes))
        let chunks = stride(from: 0, to: bytes.count, by: 230).map { offset in
            packet(offset: offset, payload: bytes.subdata(in: offset..<min(offset+230,bytes.count)), total: UInt32(bytes.count))
        }
        XCTAssertNil(try stream.append(chunks[2])); XCTAssertNil(try stream.append(chunks[2]))
        XCTAssertNil(try stream.append(chunks[0])); XCTAssertNil(try stream.append(chunks[3]))
        XCTAssertEqual(try stream.append(chunks[1]), bytes)
    }
}
