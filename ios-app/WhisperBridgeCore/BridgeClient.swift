import Foundation
import Network

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
///
/// Transport note: requests go over a raw TCP socket (Network.framework)
/// speaking HTTP/1.0 by hand, instead of URLSession. App Transport Security
/// only polices the URL loading system, and recent iOS betas have been
/// rejecting plain HTTP to Tailscale/LAN IPs even with ATS exceptions set.
/// A raw socket is not subject to ATS at all, so the receiver's plain HTTP
/// keeps working everywhere the user might connect from.
public struct BridgeClient {
    public struct Result: Equatable {
        public let ok: Bool
        public let message: String

        public init(ok: Bool, message: String) {
            self.ok = ok
            self.message = message
        }
    }

    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 5) {
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
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        guard let response = await rawPerform(
            host: host, port: port, path: "/send", method: "POST", body: body, token: token
        ) else {
            return Result(ok: false, message: "Invalid address")
        }
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
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        guard let response = await rawPerform(
            host: host, port: port, path: "/control", method: "POST", body: body, token: token
        ) else {
            return Result(ok: false, message: "Invalid address")
        }
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
        guard let response = await rawPerform(
            host: host, port: port, path: "/health", method: "GET", body: nil, token: ""
        ) else {
            return Result(ok: false, message: "Invalid address")
        }
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
        guard let response = await rawPerform(
            host: host, port: port, path: "/send", method: "POST",
            body: Data(#"{"text":""}"#.utf8), token: token
        ) else {
            return Result(ok: false, message: "Invalid address")
        }
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

    /// Minimal HTTP/1.0 request over a raw TCP socket — deliberately not
    /// URLSession, so ATS has no jurisdiction over the connection.
    private func rawPerform(
        host: String,
        port: Int,
        path: String,
        method: String,
        body: Data?,
        token: String
    ) async -> RawResponse? {
        guard BridgeEndpoint.allows(host) else { return nil }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return RawResponse(status: nil, data: Data(), error: "Invalid port")
        }

        var request = "\(method) \(path) HTTP/1.0\r\n"
        request += "Host: \(host):\(port)\r\n"
        request += "Content-Type: application/json\r\n"
        request += "Connection: close\r\n"
        if !token.isEmpty {
            request += "Authorization: Bearer \(token)\r\n"
        }
        let payload = body ?? Data()
        request += "Content-Length: \(payload.count)\r\n\r\n"
        var requestData = request.data(using: .utf8) ?? Data()
        requestData.append(payload)

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        return await withCheckedContinuation { continuation in
            // finish() is reachable from several threads at once — the global
            // timeout queue, NWConnection's state handler, and the receive
            // callbacks (all on a concurrent queue). Without a lock, two of
            // them can resume the same continuation, which is a fatal Swift
            // error. The air mouse fires ~30 requests/sec, so this race was
            // hit in practice within seconds of use.
            let lock = NSLock()
            var finished = false
            func finish(_ response: RawResponse) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: response)
            }

            // Overall request timeout.
            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                finish(RawResponse(status: nil, data: Data(), error: "Timed out"))
            }

            let parser = HTTPResponseParser()
            var requestSent = false

            func receiveMore() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        if parser.isDone {
                            finish(RawResponse(status: parser.statusCode, data: parser.body, error: nil))
                        } else {
                            finish(RawResponse(status: nil, data: Data(), error: error.localizedDescription))
                        }
                        return
                    }
                    if let data {
                        parser.append(data)
                    }
                    if parser.isDone {
                        finish(RawResponse(status: parser.statusCode, data: parser.body, error: nil))
                    } else if isComplete {
                        // Server closed without a Content-Length — treat what we
                        // have as the body if headers are complete.
                        finish(RawResponse(status: parser.statusCode, data: parser.body, error: nil))
                    } else {
                        receiveMore()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !requestSent else { return }
                    requestSent = true
                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error {
                            finish(RawResponse(status: nil, data: Data(), error: error.localizedDescription))
                        } else {
                            receiveMore()
                        }
                    })
                case .failed(let error):
                    finish(RawResponse(status: nil, data: Data(), error: error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())
        }
    }

    private func jsonDetail(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else { return "" }
        return error.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Incremental HTTP/1.x response parser. Handles Content-Length bodies (what
/// the receiver sends) plus chunked encoding and close-delimited fallbacks.
private final class HTTPResponseParser {
    private var buffer = Data()
    private var status: Int?
    private var headerEndIndex = -1
    private var headers: [String: String] = [:]
    private var bodyData = Data()
    private var bodyComplete = false
    private var chunked = false
    private var chunkRemaining = 0
    private var waitingChunkLine = false

    var isDone: Bool { bodyComplete }
    var statusCode: Int? { status }
    var body: Data { bodyData }

    func append(_ data: Data) {
        buffer.append(data)
        parse()
    }

    private func parse() {
        if headerEndIndex < 0 {
            guard let range = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return }
            headerEndIndex = range.upperBound
            parseHeaders(String(decoding: buffer[..<headerEndIndex], as: UTF8.self))
            buffer.removeSubrange(..<headerEndIndex)
        }
        if !bodyComplete {
            parseBody()
        }
    }

    private func parseHeaders(_ block: String) {
        let lines = block.components(separatedBy: "\r\n")
        if let statusLine = lines.first {
            let parts = statusLine.split(separator: " ", maxSplits: 2)
            if parts.count >= 2, parts[0].hasPrefix("HTTP/") {
                status = Int(parts[1])
            }
        }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            chunked = true
        }
    }

    private func parseBody() {
        if chunked {
            parseChunked()
            return
        }
        if let lengthText = headers["content-length"], let length = Int(lengthText) {
            if buffer.count >= length {
                bodyData.append(buffer.prefix(length))
                buffer.removeFirst(length)
                bodyComplete = true
            }
        } else {
            // No length — server will close the connection; everything read is body.
            bodyData.append(buffer)
            buffer.removeAll()
            // Completion is signalled by connection close (isComplete), not here.
        }
    }

    private func parseChunked() {
        while !bodyComplete {
            if waitingChunkLine {
                // Pull bytes until the next CRLF — the chunk size line.
                guard let crlfRange = buffer.firstRange(of: Data("\r\n".utf8)) else { break }
                guard let line = String(data: buffer[..<crlfRange.lowerBound], encoding: .ascii) else { break }
                let size = line.trimmingCharacters(in: .whitespaces).split(separator: ";").first
                chunkRemaining = Int(size ?? "", radix: 16) ?? 0
                buffer.removeSubrange(...crlfRange.upperBound)
                if chunkRemaining == 0 {
                    bodyComplete = true
                    return
                }
                waitingChunkLine = false
            } else if chunkRemaining > 0 {
                if buffer.isEmpty { break }
                let take = min(chunkRemaining, buffer.count)
                bodyData.append(buffer.prefix(take))
                buffer.removeFirst(take)
                chunkRemaining -= take
            } else {
                waitingChunkLine = true
            }
        }
    }
}
