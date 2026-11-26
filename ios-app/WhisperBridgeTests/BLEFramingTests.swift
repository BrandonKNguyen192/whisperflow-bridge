import XCTest
@testable import WhisperBridgeCore

final class BLEFramingTests: XCTestCase {
    private func payload(_ n: Int) -> Data { Data((0..<n).map { UInt8($0 % 251) }) }

    func testRoundTripAcrossManyChunks() throws {
        let data = payload(5_000)
        let frames = try BLEFraming.frames(payload: data, messageID: 0xBEEF, maxWrite: 182)
        XCTAssertTrue(frames.allSatisfy { $0.count <= 182 })
        XCTAssertEqual(frames.count, Int((5_000.0 / 175).rounded(.up)))
        var r = BLEReassembler()
        var result: BLEReassembler.Outcome = .incomplete
        for f in frames.reversed() { result = r.add(f) }   // order must not matter
        XCTAssertEqual(result, .complete(id: 0xBEEF, payload: data))
        XCTAssertEqual(r.pendingCount, 0)
    }

    func testEmptyPayloadIsOneFrame() throws {
        let frames = try BLEFraming.frames(payload: Data(), messageID: 1, maxWrite: 20)
        XCTAssertEqual(frames.count, 1)
        var r = BLEReassembler()
        XCTAssertEqual(r.add(frames[0]), .complete(id: 1, payload: Data()))
    }

    func testDuplicateChunkIsIgnored() throws {
        let data = payload(40)
        let frames = try BLEFraming.frames(payload: data, messageID: 7, maxWrite: 27)
        var r = BLEReassembler()
        XCTAssertEqual(r.add(frames[0]), .incomplete)
        XCTAssertEqual(r.add(frames[0]), .incomplete)
        XCTAssertEqual(r.add(frames[1]), .complete(id: 7, payload: data))
    }

    func testOversizedPayloadRefused() {
        XCTAssertThrowsError(try BLEFraming.frames(payload: payload(BLEProtocol.maxMessageBytes + 1),
                                                   messageID: 1, maxWrite: 512))
        XCTAssertThrowsError(try BLEFraming.frames(payload: payload(10), messageID: 1, maxWrite: 7))
    }

    func testReassemblerCapsSizeAgainstLyingHeaders() {
        var r = BLEReassembler()
        let chunk = Data(count: 500)
        var outcome: BLEReassembler.Outcome = .incomplete
        for i in 0..<200 {   // claims 1000 chunks, never finishes; > 64 KB must be dropped
            var f = Data([1, 0, 9, UInt8(i >> 8), UInt8(i & 0xFF), 0x03, 0xE8])
            f.append(chunk)
            outcome = r.add(f)
            if case .rejected = outcome { break }
        }
        XCTAssertEqual(outcome, .rejected(id: 9, reason: "Message too large"))
        XCTAssertEqual(r.pendingCount, 0)
    }

    func testIncompleteMessagesExpire() throws {
        let frames = try BLEFraming.frames(payload: payload(100), messageID: 3, maxWrite: 27)
        var r = BLEReassembler()
        let t0 = Date()
        _ = r.add(frames[0], now: t0)
        XCTAssertEqual(r.pendingCount, 1)
        r.expire(now: t0.addingTimeInterval(BLEProtocol.reassemblyTimeout + 1))
        XCTAssertEqual(r.pendingCount, 0)
    }

    func testMalformedFramesRejected() {
        var r = BLEReassembler()
        XCTAssertEqual(r.add(Data([1, 0])), .rejected(id: nil, reason: "Malformed chunk"))
        XCTAssertEqual(r.add(Data([2, 0, 1, 0, 0, 0, 1, 65])), .rejected(id: nil, reason: "Malformed chunk"))   // bad version
        XCTAssertEqual(r.add(Data([1, 0, 1, 0, 2, 0, 1, 65])), .rejected(id: nil, reason: "Malformed chunk"))   // index >= count
    }

    func testOnlyTextModesAllowed() {
        for mode in ["type", "clipboard", "append", "enter"] {
            XCTAssertNil(BLETextMessage(text: "hi", mode: mode, token: "t").rejectionReason)
        }
        XCTAssertNil(BLETextMessage(kind: "probe", text: "", token: "t").rejectionReason)
        XCTAssertNotNil(BLETextMessage(text: "", mode: "move", token: "t").rejectionReason)
        XCTAssertNotNil(BLETextMessage(kind: "control", text: "", token: "t").rejectionReason)
    }

    func testMessageJSONUsesReceiverFieldNames() throws {
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(BLETextMessage(text: "a", mode: "type", enterAfter: true, token: "t"))
        ) as? [String: Any]
        XCTAssertEqual(json?["enter_after"] as? Bool, true)
        XCTAssertNil(json?["enterAfter"])
    }

    func testLegacyProfileDecodesAsNetwork() throws {
        let legacy = #"[{"id":"7E57D8C5-8A1B-4A4B-9D7A-2C1E0F3A5B6C","name":"Mac","host":"10.0.0.2","port":9877,"token":""}]"#
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(legacy.utf8))
        XCTAssertEqual(profiles.first?.transport, .network)
        XCTAssertEqual(profiles.first?.isConfigured, true)
        XCTAssertTrue(Profile(name: "BT", transport: .bluetooth).isConfigured)
        XCTAssertFalse(Profile(name: "Empty").isConfigured)
    }
}
