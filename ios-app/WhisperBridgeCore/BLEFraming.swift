import Foundation

/// Bluetooth (text-only) wire format shared by the iOS app and the Mac helper
/// (`mac-bluetooth/`, which compiles this same file through a symlink).
///
/// A message is one JSON object (`BLETextMessage`), sealed with `BLESecurity`
/// (AES-GCM keyed by the receiver token), then split into chunks that each fit
/// one GATT write. Every chunk starts with a 7-byte header:
///
///     byte 0      version (2)
///     bytes 1-2   message id   (UInt16, big endian)
///     bytes 3-4   chunk index  (UInt16, big endian, 0-based)
///     bytes 5-6   chunk count  (UInt16, big endian)
///
/// followed by that chunk's slice of the JSON bytes. Only text actions travel
/// over Bluetooth: trackpad, air mouse and any other `/control` command are
/// rejected on both ends.
public enum BLEProtocol {
    public static let version: UInt8 = 2
    public static let headerSize = 7
    /// Largest reassembled message the Mac accepts.
    public static let maxMessageBytes = 64 * 1024
    /// Incomplete messages are dropped after this long.
    public static let reassemblyTimeout: TimeInterval = 10

    public static let serviceUUID = "6E1B0001-7A3C-4F5D-9B21-57A1B7E0B4C1"
    /// Roles: the iPhone is the peripheral (advertises this service while the app
    /// is open); the Mac helper is the central that finds and connects to it.
    /// (iPhone-as-central → Mac-as-peripheral connects hung between same-Apple-ID
    /// devices, so the roles were swapped.)
    ///
    /// iPhone → Mac framed, sealed message chunks (notify; the Mac subscribes).
    public static let messageCharacteristicUUID = "6E1B0002-7A3C-4F5D-9B21-57A1B7E0B4C1"
    /// Mac → iPhone acknowledgements (write with response): sealed `BLEAck` JSON.
    public static let ackCharacteristicUUID = "6E1B0003-7A3C-4F5D-9B21-57A1B7E0B4C1"

    /// Text modes the receiver's `/send` accepts. Nothing else crosses Bluetooth.
    public static let allowedModes: Set<String> = ["type", "clipboard", "append", "enter"]
}

/// What the iPhone sends. `kind` is "send" (deliver text) or "probe" (check the
/// token without typing anything, like the Wi-Fi Test button). The token is
/// not in the message: knowing it is proven by the `BLESecurity` seal, and the
/// Mac helper forwards with the receiver's own token file.
public struct BLETextMessage: Codable, Equatable {
    public var kind: String
    public var text: String
    public var mode: String
    public var enterAfter: Bool
    /// Unix time when sealed; the Mac rejects messages more than 5 min off.
    public var sentAt: TimeInterval

    public init(kind: String = "send", text: String, mode: String = "type", enterAfter: Bool = false,
                sentAt: TimeInterval = Date().timeIntervalSince1970) {
        self.kind = kind
        self.text = text
        self.mode = mode
        self.enterAfter = enterAfter
        self.sentAt = sentAt
    }

    enum CodingKeys: String, CodingKey {
        case kind, text, mode
        case enterAfter = "enter_after"
        case sentAt = "ts"
    }

    /// Nil when the message may be forwarded; otherwise why it is refused.
    public var rejectionReason: String? {
        switch kind {
        case "probe":
            return nil
        case "send":
            return BLEProtocol.allowedModes.contains(mode)
                ? nil
                : "Bluetooth carries text only (mode \"\(mode)\" refused)"
        default:
            return "Bluetooth carries text only (\"\(kind)\" refused)"
        }
    }
}

/// What the Mac notifies back for each message id.
public struct BLEAck: Codable, Equatable {
    public var id: UInt16
    public var ok: Bool
    public var message: String
    /// Set only on the Mac's sealed hello right after it connects: its name.
    /// Lets the iPhone show "Connected to <Mac>" and check the pairing early.
    public var mac: String?

    public init(id: UInt16, ok: Bool, message: String, mac: String? = nil) {
        self.id = id
        self.ok = ok
        self.message = message
        self.mac = mac
    }

    public static func hello(mac: String) -> BLEAck { BLEAck(id: 0, ok: true, message: "hello", mac: mac) }
    public var isHello: Bool { message == "hello" && mac != nil }
}

public enum BLEFraming {
    public enum FramingError: Error, Equatable {
        case tooLarge
        case chunkTooSmall
    }

    /// Splits `payload` into chunks no longer than `maxWrite` bytes each (header included).
    public static func frames(payload: Data, messageID: UInt16, maxWrite: Int) throws -> [Data] {
        guard payload.count <= BLEProtocol.maxMessageBytes else { throw FramingError.tooLarge }
        let body = maxWrite - BLEProtocol.headerSize
        guard body >= 1 else { throw FramingError.chunkTooSmall }
        let count = max(1, (payload.count + body - 1) / body)
        guard count <= Int(UInt16.max) else { throw FramingError.tooLarge }
        var out: [Data] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            let start = payload.startIndex + index * body
            let end = min(start + body, payload.endIndex)
            var frame = Data([BLEProtocol.version])
            frame.append(contentsOf: be(messageID))
            frame.append(contentsOf: be(UInt16(index)))
            frame.append(contentsOf: be(UInt16(count)))
            if start < end { frame.append(payload[start..<end]) }
            out.append(frame)
        }
        return out
    }

    public struct Header: Equatable {
        public let messageID: UInt16
        public let index: Int
        public let count: Int
    }

    public static func header(of frame: Data) -> Header? {
        guard frame.count >= BLEProtocol.headerSize else { return nil }
        let b = [UInt8](frame.prefix(BLEProtocol.headerSize))
        guard b[0] == BLEProtocol.version else { return nil }
        let id = UInt16(b[1]) << 8 | UInt16(b[2])
        let index = Int(UInt16(b[3]) << 8 | UInt16(b[4]))
        let count = Int(UInt16(b[5]) << 8 | UInt16(b[6]))
        guard count >= 1, index < count else { return nil }
        return Header(messageID: id, index: index, count: count)
    }

    private static func be(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
}

/// Collects chunks per message id; returns the payload once all chunks arrived.
/// Bounded: messages over `maxMessageBytes` are dropped, and incomplete ones
/// expire after `reassemblyTimeout`.
public struct BLEReassembler {
    public enum Outcome: Equatable {
        case incomplete
        case complete(id: UInt16, payload: Data)
        case rejected(id: UInt16?, reason: String)
    }

    private struct Pending {
        var count: Int
        var chunks: [Int: Data]
        var bytes: Int
        var started: Date
    }

    private var pending: [UInt16: Pending] = [:]

    public init() {}

    public var pendingCount: Int { pending.count }

    public mutating func add(_ frame: Data, now: Date = Date()) -> Outcome {
        expire(now: now)
        guard let h = BLEFraming.header(of: frame) else {
            return .rejected(id: nil, reason: "Malformed chunk")
        }
        let body = frame.dropFirst(BLEProtocol.headerSize)
        var entry = pending[h.messageID] ?? Pending(count: h.count, chunks: [:], bytes: 0, started: now)
        guard entry.count == h.count else {
            pending[h.messageID] = nil
            return .rejected(id: h.messageID, reason: "Chunk count changed mid-message")
        }
        if entry.chunks[h.index] == nil {
            entry.bytes += body.count
            entry.chunks[h.index] = Data(body)
        }
        guard entry.bytes <= BLEProtocol.maxMessageBytes else {
            pending[h.messageID] = nil
            return .rejected(id: h.messageID, reason: "Message too large")
        }
        guard entry.chunks.count == entry.count else {
            pending[h.messageID] = entry
            return .incomplete
        }
        pending[h.messageID] = nil
        var payload = Data(capacity: entry.bytes)
        for i in 0..<entry.count { payload.append(entry.chunks[i] ?? Data()) }
        return .complete(id: h.messageID, payload: payload)
    }

    public mutating func expire(now: Date = Date()) {
        pending = pending.filter { now.timeIntervalSince($0.value.started) < BLEProtocol.reassemblyTimeout }
    }
}
