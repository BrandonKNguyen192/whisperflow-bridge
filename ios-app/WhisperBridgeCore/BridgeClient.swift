import Foundation

/// The receiver intentionally uses HTTP. Keep that capability scoped to the
/// local network and Tailscale instead of allowing arbitrary internet hosts.
enum BridgeEndpoint {
    static func allows(_ rawHost: String) -> Bool {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        if ["localhost", "::1"].contains(host) || host.hasSuffix(".local") || host.hasSuffix(".ts.net") {
            return true
        }

        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]), let b = Int(parts[1]),
              let c = Int(parts[2]), let d = Int(parts[3]),
              [a, b, c, d].allSatisfy({ (0...255).contains($0) }) else {
            return host.hasPrefix("fd") || host.hasPrefix("fe80:")
        }

        return a == 10 ||
            a == 127 ||
            a == 169 && b == 254 ||
            a == 172 && (16...31).contains(b) ||
            a == 192 && b == 168 ||
            a == 100 && (64...127).contains(b)
    }
}

/// Swift port of the Android `BridgeClient` — talks the same HTTP contract as
/// the shared Python receiver (`common/bridge_server.py`).
public struct BridgeClient {
    public struct Result: Equatable {
        public let ok: Bool
        public let message: String

        public init(ok: Bool, message: String) {
            self.ok = ok
            self.message = message
        }
    }

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.session = session
        self.timeout = timeout
    }

    public static let live = BridgeClient()

    // MARK: - Text

    public func sendText(
        host: String,
        port: Int,
        text: String,
        mode: String = "type",
        source: String = "ios",
        token: String = "",
        enterAfter: Bool = false
    ) async -> Result {
        let payload: [String: Any] = [
            "text": text,
            "mode": mode,
            "source": source,
            "enter_after": enterAfter
        ]
        guard var request = makeRequest(host: host, port: port, path: "/send", token: token) else {
            return Result(ok: false, message: "Invalid address")
        }
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let response = await perform(request)
        guard let status = response.status else {
            return Result(ok: false, message: response.error ?? "Connection failed")
        }
        if (200...299).contains(status) {
            if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
               json["ok"] as? Bool == true {
                let chars = json["chars"] as? Int ?? text.count
                return Result(ok: true, message: "Sent \(chars) chars")
            }
            return Result(ok: false, message: "Server error")
        }
        let detail = jsonDetail(response.data)
        if mode == "enter" && status == 400 {
            return Result(ok: false, message: "Server needs an update or restart")
        }
        if !detail.isEmpty {
            return Result(ok: false, message: "HTTP \(status): \(detail)")
        }
        return Result(ok: false, message: "HTTP \(status)")
    }

    // MARK: - Mouse / trackpad

    public func control(
        host: String,
        port: Int,
        action: String,
        dx: Int = 0,
        dy: Int = 0,
        button: String = "left",
        token: String = ""
    ) async -> Result {
        let payload: [String: Any] = [
            "action": action,
            "dx": dx,
            "dy": dy,
            "button": button
        ]
        guard var request = makeRequest(host: host, port: port, path: "/control", token: token) else {
            return Result(ok: false, message: "Invalid address")
        }
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let response = await perform(request)
        guard let status = response.status else {
            return Result(ok: false, message: response.error ?? "Connection failed")
        }
        let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any]
        if (200...299).contains(status) {
            if json?["ok"] as? Bool == true {
                return Result(ok: true, message: json?["message"] as? String ?? "")
            }
            return Result(ok: false, message: json?["message"] as? String ?? "Mouse control failed")
        }
        let detail = jsonDetail(response.data)
        if !detail.isEmpty {
            return Result(ok: false, message: "HTTP \(status): \(detail)")
        }
        return Result(ok: false, message: "HTTP \(status)")
    }

    // MARK: - Reachability

    public func healthCheck(host: String, port: Int) async -> Result {
        guard var request = makeRequest(host: host, port: port, path: "/health", token: "") else {
            return Result(ok: false, message: "Invalid address")
        }
        request.httpMethod = "GET"
        let response = await perform(request)
        guard let status = response.status else {
            return Result(ok: false, message: response.error ?? "Unreachable")
        }
        return status == 200
            ? Result(ok: true, message: "Connected")
            : Result(ok: false, message: "HTTP \(status)")
    }

    /// Authenticated, side-effect-free probe. Mirrors Android: 401 = bad token,
    /// anything in 2xx-4xx means the host is reachable and the token is accepted.
    public func probe(host: String, port: Int, token: String) async -> Result {
        guard var request = makeRequest(host: host, port: port, path: "/send", token: token) else {
            return Result(ok: false, message: "Invalid address")
        }
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"text":""}"#.utf8)
        let response = await perform(request)
        guard let status = response.status else {
            return Result(ok: false, message: response.error ?? "Unreachable")
        }
        switch status {
        case 401:
            return Result(ok: false, message: "Bad token")
        case 200...499:
            return Result(ok: true, message: "Connected")
        default:
            return Result(ok: false, message: "HTTP \(status)")
        }
    }

    // MARK: - Plumbing

    private struct RawResponse {
        let status: Int?
        let data: Data
        let error: String?
    }

    private func makeRequest(host: String, port: Int, path: String, token: String) -> URLRequest? {
        guard BridgeEndpoint.allows(host) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async -> RawResponse {
        do {
            let (data, response) = try await session.data(for: request)
            return RawResponse(
                status: (response as? HTTPURLResponse)?.statusCode,
                data: data,
                error: nil
            )
        } catch {
            return RawResponse(status: nil, data: Data(), error: error.localizedDescription)
        }
    }

    private func jsonDetail(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else { return "" }
        return error.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
