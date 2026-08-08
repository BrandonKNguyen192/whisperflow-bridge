import Foundation

/// Swift port of the Android `Pairing` parser.
public enum Pairing {
    public struct Parsed: Equatable {
        public let host: String
        public let port: Int
        public let token: String
        public let name: String

        public init(host: String, port: Int, token: String, name: String = "") {
            self.host = host
            self.port = port
            self.token = token
            self.name = name
        }
    }

    /// True for the Tailscale CGNAT range 100.64.0.0/10.
    public static func isTailscale(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]),
              let b = Int(parts[1]) else { return false }
        return a == 100 && (64...127).contains(b)
    }

    public static func label(for host: String, suggestedName: String = "") -> String {
        let cleaned = suggestedName
            .filter { $0.isLetter || $0.isNumber || " -_.".contains($0) }
            .trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty {
            return String(cleaned.prefix(24))
        }
        return isTailscale(host) ? "Tailscale" : "MacBook Pro"
    }

    public static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            let queryItems = URLComponents(string: trimmed)?.queryItems ?? []
            func item(_ name: String) -> String? {
                queryItems.first(where: { $0.name == name })?.value
            }
            switch scheme {
            case "whisperbridge":
                guard let host = item("host")?.trimmingCharacters(in: .whitespaces),
                      !host.isEmpty else { return nil }
                return Parsed(
                    host: host,
                    port: item("port").flatMap(Int.init) ?? 9877,
                    token: item("token") ?? "",
                    name: item("name") ?? ""
                )
            case "http", "https":
                guard let host = url.host?.trimmingCharacters(in: .whitespaces),
                      !host.isEmpty else { return nil }
                return Parsed(
                    host: host,
                    port: url.port ?? 9877,
                    token: item("token") ?? "",
                    name: item("name") ?? ""
                )
            default:
                break
            }
        }

        // Bare "host:port" fallback.
        if trimmed.contains(":") && !trimmed.contains(" ") {
            let host = String(trimmed.prefix(while: { $0 != ":" }))
            let portPart = trimmed.split(separator: ":").dropFirst().first ?? ""
            if !host.isEmpty {
                return Parsed(host: host, port: Int(portPart) ?? 9877, token: "")
            }
        }
        return nil
    }
}
