import XCTest
@testable import BridgeBLECore

final class BridgeBLECoreTests: XCTestCase {
    private func encode(_ m: BLETextMessage) -> Data { try! JSONEncoder().encode(m) }
    private func sealed(_ m: BLETextMessage, token: String = "tok") -> Data {
        try! BLESecurity.seal(encode(m), key: BLESecurity.key(token: token), direction: .message)
    }

    func testFramesFromPhoneReassembleOnMac() throws {
        let text = String(repeating: "héllo wörld 👋 ", count: 300)
        let payload = sealed(BLETextMessage(text: text, mode: "type"))
        let frames = try BLEFraming.frames(payload: payload, messageID: 42, maxWrite: 185)
        var r = BLEReassembler()
        var out: BLEReassembler.Outcome = .incomplete
        for f in frames { out = r.add(f) }
        XCTAssertEqual(out, .complete(id: 42, payload: payload))
    }

    func testForwardBuildsReceiverRequestWithFileToken() throws {
        var replay = BLEReplayGuard()
        let decision = ReceiverForwarder(port: 9877).decide(
            sealed: sealed(BLETextMessage(text: "hi", mode: "clipboard", enterAfter: true), token: "secret"),
            token: "secret", replay: &replay)
        guard case .forward(let req, let isProbe) = decision else { return XCTFail("refused: \(decision)") }
        XCTAssertFalse(isProbe)
        XCTAssertEqual(req.url?.absoluteString, "http://127.0.0.1:9877/send")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["text"] as? String, "hi")
        XCTAssertEqual(body["mode"] as? String, "clipboard")
        XCTAssertEqual(body["enter_after"] as? Bool, true)
        XCTAssertEqual(body["source"] as? String, "ios-bluetooth")
    }

    func testWrongTokenStaleAndReplayRefused() {
        let f = ReceiverForwarder()
        var replay = BLEReplayGuard()
        guard case .refuse(let wrong) = f.decide(sealed: sealed(BLETextMessage(text: "x"), token: "old"),
                                                 token: "new", replay: &replay) else { return XCTFail() }
        XCTAssertTrue(wrong.contains("Pair iPhone"))
        let stale = sealed(BLETextMessage(text: "x", sentAt: Date().timeIntervalSince1970 - 3600))
        XCTAssertEqual(f.decide(sealed: stale, token: "tok", replay: &replay),
                       .refuse("Message too old — check the iPhone and Mac clocks"))
        let once = sealed(BLETextMessage(text: "x"))
        if case .refuse = f.decide(sealed: once, token: "tok", replay: &replay) { XCTFail() }
        XCTAssertEqual(f.decide(sealed: once, token: "tok", replay: &replay), .refuse("Duplicate message ignored"))
    }

    func testProbeSendsEmptyText() throws {
        var replay = BLEReplayGuard()
        guard case .forward(let req, let isProbe) = ReceiverForwarder().decide(
            sealed: sealed(BLETextMessage(kind: "probe", text: "")), token: "tok", replay: &replay) else { return XCTFail() }
        XCTAssertTrue(isProbe)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual(body["text"] as? String, "")
    }

    func testNoTokenNoAuthHeader() {
        var replay = BLEReplayGuard()
        guard case .forward(let req, _) = ReceiverForwarder().decide(
            sealed: sealed(BLETextMessage(text: "x"), token: ""), token: "", replay: &replay) else { return XCTFail() }
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testTrackpadAndUnknownRefused() {
        let f = ReceiverForwarder()
        var replay = BLEReplayGuard()
        if case .forward = f.decide(sealed: sealed(BLETextMessage(text: "", mode: "move")), token: "tok", replay: &replay) { XCTFail() }
        if case .forward = f.decide(sealed: sealed(BLETextMessage(kind: "control", text: "")), token: "tok", replay: &replay) { XCTFail() }
        if case .forward = f.decide(sealed: Data("{}".utf8), token: "tok", replay: &replay) { XCTFail() }
    }

    func testAckIsSealed() throws {
        let ack = BLEAck(id: 3, ok: true, message: "Sent 2 chars over Bluetooth")
        let data = try XCTUnwrap(ReceiverForwarder.seal(ack, token: "tok"))
        let plain = try BLESecurity.open(data, key: BLESecurity.key(token: "tok"), direction: .ack)
        XCTAssertEqual(try JSONDecoder().decode(BLEAck.self, from: plain), ack)
    }

    func testAckMapping() {
        let ok = ReceiverForwarder.ack(id: 1, isProbe: false, status: 200,
                                       body: Data(#"{"ok":true,"chars":5}"#.utf8), error: nil)
        XCTAssertEqual(ok, BLEAck(id: 1, ok: true, message: "Sent 5 chars over Bluetooth"))
        XCTAssertFalse(ReceiverForwarder.ack(id: 1, isProbe: false, status: 401, body: nil, error: nil).ok)
        XCTAssertFalse(ReceiverForwarder.ack(id: 1, isProbe: true, status: 401, body: nil, error: nil).ok)
        XCTAssertTrue(ReceiverForwarder.ack(id: 1, isProbe: true, status: 400, body: nil, error: nil).ok)
        let down = ReceiverForwarder.ack(id: 1, isProbe: false, status: nil, body: nil, error: "refused")
        XCTAssertFalse(down.ok)
        XCTAssertTrue(down.message.contains("receiver not running"))
        let bad = ReceiverForwarder.ack(id: 1, isProbe: false, status: 400,
                                        body: Data(#"{"ok":false,"error":"source must be a string"}"#.utf8), error: nil)
        XCTAssertEqual(bad.message, "HTTP 400: source must be a string")
    }

    func testBluetoothPairingLink() {
        let link = PairingLink.bluetooth(token: "a+b/c=d&e", macName: "Brandon’s MacBook Air", port: 9877)
        XCTAssertTrue(link.hasPrefix("whisperbridge://pair?transport=bluetooth&port=9877"))
        let items = URLComponents(string: link)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("transport"), "bluetooth")
        XCTAssertEqual(value("token"), "a+b/c=d&e")
        XCTAssertEqual(value("name"), "Brandon’s MacBook Air")
        XCTAssertNil(value("host"))
        XCTAssertFalse(PairingLink.bluetooth(token: "", macName: "", port: 9877).contains("token="))
    }

    func testReadTokenTrimsAndToleratesMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wb-token-\(UUID().uuidString)")
        try "  secret-token\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(PairingLink.readToken(path: url.path), "secret-token")
        XCTAssertEqual(PairingLink.readToken(path: url.path + "-missing"), "")
    }
}
