import CryptoKit
import Foundation

/// App-layer security for the Bluetooth transport (shared with the Mac helper
/// through a symlink).
///
/// Why not OS Bluetooth pairing: an iPhone and a Mac on the same Apple ID
/// already share Continuity keys and an LE link, and encryption-required
/// characteristics there either never prompt or stall the connection. So the
/// GATT characteristics are open, and every message is sealed instead:
///
///     key   = HKDF-SHA256(receiver token, salt "whisperbridge", info "whisperbridge-ble-v2")
///     frame = 0x02 | AES-GCM combined (12-byte nonce | ciphertext | 16-byte tag)
///     AAD   = "msg" (iPhone → Mac) or "ack" (Mac → iPhone)
///
/// Only someone who knows the receiver token (from the pairing QR) can produce
/// a message the Mac accepts, nobody nearby can read the text, and the token
/// itself never crosses the air. The Mac also rejects stale (> 5 min) and
/// replayed messages.
public enum BLESecurity {
    public static let version: UInt8 = 2
    public static let maxClockSkew: TimeInterval = 300

    public enum Direction: String { case message = "msg", ack = "ack" }

    public enum Failure: Error, Equatable {
        case malformed, wrongKey, stale, replayed
    }

    public static func key(token: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(token.utf8)),
            salt: Data("whisperbridge".utf8),
            info: Data("whisperbridge-ble-v2".utf8),
            outputByteCount: 32)
    }

    public static func seal(_ plaintext: Data, key: SymmetricKey, direction: Direction) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(direction.rawValue.utf8))
        guard let combined = box.combined else { throw Failure.malformed }
        return Data([version]) + combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey, direction: Direction) throws -> Data {
        guard sealed.count > 1 + 12 + 16, sealed.first == version else { throw Failure.malformed }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst())
            return try AES.GCM.open(box, using: key, authenticating: Data(direction.rawValue.utf8))
        } catch {
            throw Failure.wrongKey
        }
    }

    /// The 12-byte GCM nonce, used as the replay-cache id.
    public static func nonce(of sealed: Data) -> Data? {
        sealed.count > 13 ? Data(sealed.dropFirst().prefix(12)) : nil
    }
}

/// Remembers recently seen message nonces so a recorded message can't be replayed.
public struct BLEReplayGuard {
    private var seen: [Data: Date] = [:]
    public init() {}

    /// Checks freshness and uniqueness; records the nonce when accepted.
    public mutating func accept(nonce: Data, sentAt: TimeInterval, now: Date = Date()) -> BLESecurity.Failure? {
        let window = BLESecurity.maxClockSkew
        seen = seen.filter { now.timeIntervalSince($0.value) < 2 * window }
        if abs(now.timeIntervalSince1970 - sentAt) > window { return .stale }
        if seen[nonce] != nil { return .replayed }
        seen[nonce] = now
        return nil
    }
}
