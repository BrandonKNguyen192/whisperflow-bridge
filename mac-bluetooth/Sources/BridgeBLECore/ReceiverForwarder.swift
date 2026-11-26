import Foundation

/// Turns a reassembled Bluetooth message into the existing receiver's HTTP
/// contract (`POST /send` on 127.0.0.1, same JSON and Bearer token as the
/// Wi-Fi apps) and maps the answer to a `BLEAck`. The helper keeps no secrets:
/// the token arrives inside each message and the receiver still checks it.
public struct ReceiverForwarder {
    public var port: Int
    public var timeout: TimeInterval

    public init(port: Int = 9877, timeout: TimeInterval = 10) {
        self.port = port
        self.timeout = timeout
    }

    public enum Decision: Equatable {
        case forward(URLRequest)
        case refuse(String)
    }

    /// Builds the request, or refuses anything that isn't text.
    public func decide(payload: Data) -> Decision {
        guard let message = try? JSONDecoder().decode(BLETextMessage.self, from: payload) else {
            return .refuse("Unreadable message")
        }
        if let reason = message.rejectionReason { return .refuse(reason) }

        var url = URLComponents()
        url.scheme = "http"
        url.host = "127.0.0.1"
        url.port = port
        url.path = "/send"
        var request = URLRequest(url: url.url!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !message.token.isEmpty {
            request.setValue("Bearer \(message.token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = message.kind == "probe"
            ? ["text": ""]   // same side-effect-free probe the iOS Test button uses over Wi-Fi
            : ["text": message.text, "mode": message.mode, "source": "ios-bluetooth",
               "enter_after": message.enterAfter]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return .forward(request)
    }

    /// Maps the receiver's answer to an ack. `isProbe` mirrors BridgeClient.probe:
    /// 401 = bad token, anything else below 500 = reachable and accepted.
    public static func ack(id: UInt16, isProbe: Bool, status: Int?, body: Data?, error: String?) -> BLEAck {
        guard let status else {
            return BLEAck(id: id, ok: false,
                          message: "Mac receiver not running (\(error ?? "no answer")) — start Whisper Bridge on the Mac")
        }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if status == 401 { return BLEAck(id: id, ok: false, message: "Bad token — scan the pairing QR again") }
        if isProbe {
            return status < 500 ? BLEAck(id: id, ok: true, message: "Connected")
                                : BLEAck(id: id, ok: false, message: "HTTP \(status)")
        }
        if (200...299).contains(status), json?["ok"] as? Bool == true {
            let chars = json?["chars"] as? Int ?? 0
            return BLEAck(id: id, ok: true, message: "Sent \(chars) chars over Bluetooth")
        }
        if let detail = json?["error"] as? String, !detail.isEmpty {
            return BLEAck(id: id, ok: false, message: "HTTP \(status): \(detail)")
        }
        return BLEAck(id: id, ok: false, message: (200...299).contains(status) ? "Receiver error" : "HTTP \(status)")
    }

    public static func isProbe(_ payload: Data) -> Bool {
        (try? JSONDecoder().decode(BLETextMessage.self, from: payload))?.kind == "probe"
    }
}
