import XCTest
import Network
@testable import WhisperBridgeCore

/// Tiny in-process HTTP/1.0 receiver built on Network.framework. Exercises
/// the real raw-TCP transport the app uses instead of stubbing URLSession.
final class MockReceiver {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "mock-receiver")

    private(set) var lastRequest: String = ""
    private(set) var requestCount = 0
    var statusCode = 200
    var responseJSON: [String: Any] = ["ok": true, "chars": 5]

    var port: Int {
        // The listener picks a random port shortly after start; wait for it
        // (generous — right after another listener is cancelled it can lag).
        for _ in 0..<10_000 where listener.port == nil {
            Thread.sleep(forTimeInterval: 0.001)
        }
        return Int(listener.port?.rawValue ?? 0)
    }

    init() throws {
        listener = try NWListener(using: .tcp)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.handle(connection)
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        var requestData = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let data {
                    requestData.append(data)
                }
                if let error {
                    return
                }
                if let bodyLength = Self.bodyLength(of: requestData) {
                    if requestData.count >= bodyLength {
                        self.requestCount += 1
                        self.lastRequest = String(decoding: requestData, as: UTF8.self)
                        self.respond(to: connection)
                    } else {
                        receiveMore()
                    }
                } else {
                    receiveMore()
                }
            }
        }

        receiveMore()
    }

    private static func bodyLength(of data: Data) -> Int? {
        guard let range = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: data[..<range.lowerBound], as: UTF8.self)
        let length = header.split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
                else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0
        return range.upperBound + length
    }

    private func respond(to connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: responseJSON)) ?? Data()
        let reason: String
        switch statusCode {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        default: reason = "Error"
        }
        let head = "HTTP/1.0 \(statusCode) \(reason)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var response = head.data(using: .utf8) ?? Data()
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

final class BridgeClientTests: XCTestCase {
    private var receiver: MockReceiver!
    private var client: BridgeClient!

    override func setUp() {
        super.setUp()
        receiver = try! MockReceiver()
        client = BridgeClient(timeout: 2)
    }

    override func tearDown() {
        receiver.stop()
        receiver = nil
        super.tearDown()
    }

    private func requestBody() throws -> [String: Any] {
        let raw = receiver.lastRequest
        guard let range = raw.range(of: "\r\n\r\n") else {
            throw XCTSkip("no header/body split in captured request")
        }
        let body = String(raw[range.upperBound...])
        let data = try XCTUnwrap(body.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSendTextSendsAuthAndPayload() async throws {
        let result = await client.sendText(
            host: "127.0.0.1",
            port: receiver.port,
            text: "hello",
            token: "secret"
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "Sent 5 chars")

        XCTAssertTrue(receiver.lastRequest.hasPrefix("POST /send HTTP/1.0"))
        XCTAssertTrue(
            receiver.lastRequest.localizedCaseInsensitiveContains("Authorization: Bearer secret")
        )
        let json = try requestBody()
        XCTAssertEqual(json["text"] as? String, "hello")
        XCTAssertEqual(json["mode"] as? String, "type")
        XCTAssertEqual(json["enter_after"] as? Bool, false)
    }

    func testBadTokenFromProbe() async {
        receiver.statusCode = 401
        receiver.responseJSON = ["ok": false, "error": "unauthorized"]
        let result = await client.probe(host: "127.0.0.1", port: receiver.port, token: "bad")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.message, "Bad token")
    }

    func testEnter400HintsServerUpdate() async {
        receiver.statusCode = 400
        receiver.responseJSON = ["ok": false, "error": "empty text"]
        let result = await client.sendText(host: "127.0.0.1", port: receiver.port, text: "", mode: "enter")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.message, "Server needs an update or restart")
    }

    func testControlSendsDeltas() async throws {
        let result = await client.control(
            host: "127.0.0.1",
            port: receiver.port,
            action: "move",
            dx: 12,
            dy: -4,
            button: "left"
        )
        XCTAssertTrue(result.ok)
        XCTAssertTrue(receiver.lastRequest.hasPrefix("POST /control HTTP/1.0"))
        let json = try requestBody()
        XCTAssertEqual(json["action"] as? String, "move")
        XCTAssertEqual(json["dx"] as? Int, 12)
        XCTAssertEqual(json["dy"] as? Int, -4)
        XCTAssertEqual(json["button"] as? String, "left")
    }

    func testNetworkFailureMapsMessage() async {
        // Nothing listens on port 1 — connection will fail fast.
        let result = await client.healthCheck(host: "127.0.0.1", port: 1)
        XCTAssertFalse(result.ok)
        XCTAssertFalse(result.message.isEmpty)
    }

    func testEndpointPolicyAllowsBridgeNetworksOnly() {
        XCTAssertTrue(BridgeEndpoint.allows("192.168.1.5"))
        XCTAssertTrue(BridgeEndpoint.allows("100.105.11.31"))
        XCTAssertTrue(BridgeEndpoint.allows("macbook-pro.local"))
        XCTAssertTrue(BridgeEndpoint.allows("macbook.tailnet.ts.net"))
        XCTAssertFalse(BridgeEndpoint.allows("example.com"))
        XCTAssertFalse(BridgeEndpoint.allows("8.8.8.8"))
    }
}
