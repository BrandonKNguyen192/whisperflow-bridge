import XCTest
@testable import BridgeBLECore

final class BridgeBLECoreTests: XCTestCase {
    private func encode(_ m: BLETextMessage) -> Data { try! JSONEncoder().encode(m) }

    func testFramesFromPhoneReassembleOnMac() throws {
        let text = String(repeating: "héllo wörld 👋 ", count: 300)
        let payload = encode(BLETextMessage(text: text, mode: "type", token: "tok"))
        let frames = try BLEFraming.frames(payload: payload, messageID: 42, maxWrite: 185)
        var r = BLEReassembler()
        var out: BLEReassembler.Outcome = .incomplete
        for f in frames { out = r.add(f) }
        XCTAssertEqual(out, .complete(id: 42, payload: payload))
    }

    func testForwardBuildsReceiverRequest() throws {
        let decision = ReceiverForwarder(port: 9877).decide(
            payload: encode(BLETextMessage(text: "hi", mode: "clipboard", enterAfter: true, token: "secret")))
        guard case .forward(let req) = decision else { return XCTFail("refused") }
        XCTAssertEqual(req.url?.absoluteString, "http://127.0.0.1:9877/send")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["text"] as? String, "hi")
        XCTAssertEqual(body["mode"] as? String, "clipboard")
        XCTAssertEqual(body["enter_after"] as? Bool, true)
        XCTAssertEqual(body["source"] as? String, "ios-bluetooth")
    }

    func testProbeSendsEmptyText() throws {
        guard case .forward(let req) = ReceiverForwarder().decide(
            payload: encode(BLETextMessage(kind: "probe", text: "", token: "t"))) else { return XCTFail() }
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual(body["text"] as? String, "")
    }

    func testNoTokenNoAuthHeader() {
        guard case .forward(let req) = ReceiverForwarder().decide(
            payload: encode(BLETextMessage(text: "x", token: ""))) else { return XCTFail() }
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testTrackpadAndUnknownRefused() {
        let f = ReceiverForwarder()
        if case .forward = f.decide(payload: encode(BLETextMessage(text: "", mode: "move", token: "t"))) { XCTFail() }
        if case .forward = f.decide(payload: encode(BLETextMessage(kind: "control", text: "", token: "t"))) { XCTFail() }
        XCTAssertEqual(f.decide(payload: Data("{}".utf8)), .refuse("Unreadable message"))
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
