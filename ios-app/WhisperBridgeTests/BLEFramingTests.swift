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
            var f = Data([2, 0, 9, UInt8(i >> 8), UInt8(i & 0xFF), 0x03, 0xE8])
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
        XCTAssertEqual(r.add(Data([3, 0, 1, 0, 0, 0, 1, 65])), .rejected(id: nil, reason: "Malformed chunk"))   // bad version
        XCTAssertEqual(r.add(Data([2, 0, 1, 0, 2, 0, 1, 65])), .rejected(id: nil, reason: "Malformed chunk"))   // index >= count
    }

    func testOnlyTextModesAllowed() {
        for mode in ["type", "clipboard", "append", "enter"] {
            XCTAssertNil(BLETextMessage(text: "hi", mode: mode).rejectionReason)
        }
        XCTAssertNil(BLETextMessage(kind: "probe", text: "").rejectionReason)
        XCTAssertNotNil(BLETextMessage(text: "", mode: "move").rejectionReason)
        XCTAssertNotNil(BLETextMessage(kind: "control", text: "").rejectionReason)
    }

    func testMessageJSONUsesReceiverFieldNames() throws {
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(BLETextMessage(text: "a", mode: "type", enterAfter: true))
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

    func testSealOpenRoundTripAndWrongKey() throws {
        let key = BLESecurity.key(token: "receiver-token")
        let plain = Data("hello ✈️".utf8)
        let sealed = try BLESecurity.seal(plain, key: key, direction: .message)
        XCTAssertEqual(sealed.first, BLESecurity.version)
        XCTAssertNil(sealed.range(of: plain))                       // text is not readable on the air
        XCTAssertEqual(try BLESecurity.open(sealed, key: key, direction: .message), plain)
        XCTAssertThrowsError(try BLESecurity.open(sealed, key: BLESecurity.key(token: "other"), direction: .message)) {
            XCTAssertEqual($0 as? BLESecurity.Failure, .wrongKey)
        }
        // A message can't be reflected back as an ack.
        XCTAssertThrowsError(try BLESecurity.open(sealed, key: key, direction: .ack))
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try BLESecurity.open(tampered, key: key, direction: .message))
        XCTAssertThrowsError(try BLESecurity.open(Data([2, 1, 2]), key: key, direction: .message)) {
            XCTAssertEqual($0 as? BLESecurity.Failure, .malformed)
        }
        XCTAssertNoThrow(try BLESecurity.seal(plain, key: BLESecurity.key(token: ""), direction: .message))
    }

    func testReplayGuard() {
        var guardian = BLEReplayGuard()
        let now = Date()
        let nonce = Data(repeating: 7, count: 12)
        XCTAssertNil(guardian.accept(nonce: nonce, sentAt: now.timeIntervalSince1970, now: now))
        XCTAssertEqual(guardian.accept(nonce: nonce, sentAt: now.timeIntervalSince1970, now: now), .replayed)
        XCTAssertEqual(guardian.accept(nonce: Data(repeating: 8, count: 12),
                                       sentAt: now.timeIntervalSince1970 - 600, now: now), .stale)
    }

    func testHelloAckRoundTripAndPlainAckCompat() throws {
        let key = BLESecurity.key(token: "tok")
        let sealed = try BLESecurity.seal(JSONEncoder().encode(BLEAck.hello(mac: "Brandon’s MacBook Air")),
                                          key: key, direction: .ack)
        let ack = try JSONDecoder().decode(BLEAck.self, from: BLESecurity.open(sealed, key: key, direction: .ack))
        XCTAssertTrue(ack.isHello)
        XCTAssertEqual(ack.mac, "Brandon’s MacBook Air")
        let plain = try JSONDecoder().decode(BLEAck.self, from: Data(#"{"id":4,"ok":false,"message":"nope"}"#.utf8))
        XCTAssertFalse(plain.isHello)
        XCTAssertNil(plain.mac)
    }
}
