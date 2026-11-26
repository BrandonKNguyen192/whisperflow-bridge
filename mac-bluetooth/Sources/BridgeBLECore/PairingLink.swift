import Foundation

/// The QR the helper shows under "Pair iPhone…": the receiver's existing
/// `whisperbridge://pair` link plus `transport=bluetooth`, so the iPhone makes
/// a "<Mac> · Bluetooth" profile on its own. No host: Bluetooth finds the Mac
/// by service UUID.
public enum PairingLink {
    public static let tokenPath = "~/.config/whisperbridge/token"

    public static func bluetooth(token: String, macName: String, port: Int = 9877) -> String {
        var link = "whisperbridge://pair?transport=bluetooth&port=\(port)"
        if !token.isEmpty { link += "&token=" + encode(token) }
        if !macName.isEmpty { link += "&name=" + encode(macName) }
        return link
    }

    /// Reads the receiver's token the same way install.command does (trimmed).
    /// Returns "" when there is no token file. Never logged.
    public static func readToken(path: String = tokenPath) -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strict query encoding: only unreserved characters stay literal, so
    /// '+', '&', '=' and spaces in tokens or Mac names survive the round trip.
    static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
