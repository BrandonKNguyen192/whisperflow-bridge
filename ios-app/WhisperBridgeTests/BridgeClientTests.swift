import XCTest
@testable import WhisperBridgeCore

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class BridgeClientTests: XCTestCase {
    private var capturedRequest: URLRequest?
    private var client: BridgeClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        client = BridgeClient(session: URLSession(configuration: config), timeout: 2)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        capturedRequest = nil
        super.tearDown()
    }

    private func stub(status: Int, json: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        StubURLProtocol.handler = { request in
            self.capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
    }

    /// URLSession rewrites the body into `httpBodyStream` by the time a
    /// URLProtocol sees the request, so read from either representation.
    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    func testSendTextSendsAuthAndPayload() async throws {
        stub(status: 200, json: ["ok": true, "chars": 5])
        let result = await client.sendText(
            host: "192.168.1.5",
            port: 9877,
            text: "hello",
            token: "secret"
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "Sent 5 chars")

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/send")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try XCTUnwrap(bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "hello")
        XCTAssertEqual(json["mode"] as? String, "type")
        XCTAssertEqual(json["enter_after"] as? Bool, false)
    }

    func testBadTokenFromProbe() async {
        stub(status: 401, json: ["ok": false, "error": "unauthorized"])
        let result = await client.probe(host: "192.168.1.5", port: 9877, token: "bad")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.message, "Bad token")
    }

    func testEnter400HintsServerUpdate() async {
        stub(status: 400, json: ["ok": false, "error": "empty text"])
        let result = await client.sendText(host: "192.168.1.5", port: 9877, text: "", mode: "enter")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.message, "Server needs an update or restart")
    }

    func testControlSendsDeltas() async throws {
        stub(status: 200, json: ["ok": true, "message": ""])
        let result = await client.control(
            host: "192.168.1.5",
            port: 9877,
            action: "move",
            dx: 12,
            dy: -4,
            button: "left"
        )
        XCTAssertTrue(result.ok)
        let body = try XCTUnwrap(bodyData(from: XCTUnwrap(capturedRequest)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["action"] as? String, "move")
        XCTAssertEqual(json["dx"] as? Int, 12)
        XCTAssertEqual(json["dy"] as? Int, -4)
        XCTAssertEqual(json["button"] as? String, "left")
    }

    func testNetworkFailureMapsMessage() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let result = await client.healthCheck(host: "192.168.1.5", port: 9877)
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
