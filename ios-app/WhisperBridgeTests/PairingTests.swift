import XCTest
@testable import WhisperBridgeCore

final class PairingTests: XCTestCase {
    func testWhisperbridgePayload() {
        let parsed = Pairing.parse(
            "whisperbridge://pair?host=192.168.1.5&port=9877&token=abc123&name=MacBook%20Pro"
        )
        XCTAssertEqual(parsed?.host, "192.168.1.5")
        XCTAssertEqual(parsed?.port, 9877)
        XCTAssertEqual(parsed?.token, "abc123")
        XCTAssertEqual(parsed?.name, "MacBook Pro")
    }

    func testHttpPayloadWithPort() {
        let parsed = Pairing.parse("http://100.105.11.31:9999?token=tok&name=Mac%20Studio")
        XCTAssertEqual(parsed?.host, "100.105.11.31")
        XCTAssertEqual(parsed?.port, 9999)
        XCTAssertEqual(parsed?.token, "tok")
        XCTAssertEqual(parsed?.name, "Mac Studio")
    }

    func testTailscaleDetectionAndLabels() {
        XCTAssertTrue(Pairing.isTailscale("100.105.11.31"))
        XCTAssertFalse(Pairing.isTailscale("192.168.1.5"))
        XCTAssertEqual(Pairing.label(for: "100.105.11.31"), "Tailscale")
        XCTAssertEqual(Pairing.label(for: "192.168.1.5"), "MacBook Pro")
        XCTAssertEqual(Pairing.label(for: "192.168.1.5", suggestedName: "Mac Studio"), "Mac Studio")
    }

    func testBareHostPort() {
        let parsed = Pairing.parse("192.168.1.10:9000")
        XCTAssertEqual(parsed?.host, "192.168.1.10")
        XCTAssertEqual(parsed?.port, 9000)
    }

    func testGarbageRejected() {
        XCTAssertNil(Pairing.parse(""))
        XCTAssertNil(Pairing.parse("not a link at all"))
        XCTAssertNil(Pairing.parse("hello world:1234"))
    }
}
