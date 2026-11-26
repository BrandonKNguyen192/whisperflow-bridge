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

    func testBluetoothLinkParses() {
        let parsed = Pairing.parse(
            "whisperbridge://pair?transport=bluetooth&token=t0k&name=Brandon%E2%80%99s%20MacBook%20Air"
        )
        XCTAssertEqual(parsed?.transport, .bluetooth)
        XCTAssertEqual(parsed?.token, "t0k")
        XCTAssertEqual(parsed?.name, "Brandon’s MacBook Air")
        XCTAssertEqual(parsed?.host, "")
    }

    func testLinksWithoutTransportStayNetwork() {
        XCTAssertEqual(Pairing.parse("whisperbridge://pair?host=10.0.0.2&token=a")?.transport, .network)
        XCTAssertEqual(Pairing.parse("whisperbridge://pair?host=10.0.0.2&transport=wifi")?.transport, .network)
        XCTAssertNil(Pairing.parse("whisperbridge://pair?token=a"))   // network links still need a host
    }

    func testBluetoothPairingCreatesSelectsAndRefreshesProfile() {
        let suite = "pairing-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileStore(defaults: defaults)
        store.add(name: "Studio", host: "10.0.0.2")
        XCTAssertEqual(store.activeIndex, 0)

        let link = Pairing.parse("whisperbridge://pair?transport=bluetooth&token=one&name=Air")!
        let index = store.applyBluetoothPairing(link)
        XCTAssertEqual(index, 1)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.active?.name, "Air · Bluetooth")
        XCTAssertEqual(store.active?.transport, .bluetooth)
        XCTAssertEqual(store.active?.token, "one")
        XCTAssertEqual(store.profiles[0].transport, .network)   // untouched

        // Re-scanning the same Mac refreshes the token instead of duplicating.
        store.setActive(0)
        let again = store.applyBluetoothPairing(
            Pairing.parse("whisperbridge://pair?transport=bluetooth&token=two&name=Air")!)
        XCTAssertEqual(again, 1)
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.active?.token, "two")

        // Survives a reload.
        let reloaded = ProfileStore(defaults: defaults)
        XCTAssertEqual(reloaded.active?.name, "Air · Bluetooth")
        XCTAssertEqual(reloaded.active?.transport, .bluetooth)
    }

    func testBluetoothProfileNameFallback() {
        XCTAssertEqual(ProfileStore.bluetoothProfileName(for: ""), "Mac · Bluetooth")
        XCTAssertEqual(ProfileStore.bluetoothProfileName(for: "Mac<script>"), "Macscript · Bluetooth")
    }
}
