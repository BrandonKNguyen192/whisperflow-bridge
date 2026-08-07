// Whisper Bridge — macOS mouse driver.
//
// Compiled once by bridge_server.py into ~/.cache/whisperbridge/mouse_helper
// and then invoked with a single JSON argument per event. Uses CoreGraphics
// event taps, so the host app needs Accessibility permission; the helper
// requests it via CGRequestPostEventAccess when it is missing.

import Foundation
import CoreGraphics

struct ControlArgs: Codable {
    let action: String
    var dx: Int = 0
    var dy: Int = 0
    var button: String = "left"
    var x: Int? = nil
    var y: Int? = nil

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        dx = try container.decodeIfPresent(Int.self, forKey: .dx) ?? 0
        dy = try container.decodeIfPresent(Int.self, forKey: .dy) ?? 0
        button = try container.decodeIfPresent(String.self, forKey: .button) ?? "left"
        x = try container.decodeIfPresent(Int.self, forKey: .x)
        y = try container.decodeIfPresent(Int.self, forKey: .y)
    }
}

enum HelperError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

func writeJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func currentPoint() -> CGPoint {
    if let event = CGEvent(source: nil) {
        return event.location
    }
    return CGPoint(x: 0, y: 0)
}

func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: button
    ) else { return }
    event.post(tap: .cghidEventTap)
}

func click(at point: CGPoint, button: CGMouseButton) {
    switch button {
    case .right:
        post(.rightMouseDown, at: point, button: .right)
        post(.rightMouseUp, at: point, button: .right)
    case .center:
        post(.otherMouseDown, at: point, button: .center)
        post(.otherMouseUp, at: point, button: .center)
    default:
        post(.leftMouseDown, at: point, button: .left)
        post(.leftMouseUp, at: point, button: .left)
    }
}

func perform(_ args: ControlArgs) throws {
    let cursor = currentPoint()
    let button: CGMouseButton = args.button == "right" ? .right
        : args.button == "middle" ? .center
        : .left

    switch args.action {
    case "move":
        let target = CGPoint(x: cursor.x + CGFloat(args.dx), y: cursor.y + CGFloat(args.dy))
        post(.mouseMoved, at: target, button: button)

    case "click":
        let target: CGPoint
        if let x = args.x, let y = args.y {
            target = CGPoint(x: CGFloat(x), y: CGFloat(y))
        } else {
            target = cursor
        }
        click(at: target, button: button)

    case "double_click":
        let target = cursor
        for _ in 0..<2 {
            click(at: target, button: button)
            usleep(40_000)
        }

    case "drag":
        let target = CGPoint(x: cursor.x + CGFloat(args.dx), y: cursor.y + CGFloat(args.dy))
        post(.leftMouseDown, at: cursor, button: .left)
        post(.leftMouseDragged, at: target, button: .left)
        post(.leftMouseUp, at: target, button: .left)

    case "down":
        switch button {
        case .right:
            post(.rightMouseDown, at: cursor, button: .right)
        case .center:
            post(.otherMouseDown, at: cursor, button: .center)
        default:
            post(.leftMouseDown, at: cursor, button: .left)
        }

    case "up":
        switch button {
        case .right:
            post(.rightMouseUp, at: cursor, button: .right)
        case .center:
            post(.otherMouseUp, at: cursor, button: .center)
        default:
            post(.leftMouseUp, at: cursor, button: .left)
        }

    case "scroll":
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(args.dy),
            wheel2: Int32(args.dx),
            wheel3: 0
        ) else {
            throw HelperError.message("could not build scroll event")
        }
        event.post(tap: .cghidEventTap)

    default:
        throw HelperError.message("unknown action \(args.action)")
    }
}

guard CommandLine.arguments.count >= 2 else {
    writeJSON(["ok": false, "error": "missing JSON argument"])
    exit(1)
}

guard let data = CommandLine.arguments[1].data(using: .utf8),
      let args = try? JSONDecoder().decode(ControlArgs.self, from: data) else {
    writeJSON(["ok": false, "error": "invalid JSON argument"])
    exit(1)
}

if !CGPreflightPostEventAccess() {
    _ = CGRequestPostEventAccess()
    writeJSON([
        "ok": false,
        "error": "Mac needs Accessibility permission for mouse control — grant it in System Settings → Privacy & Security → Accessibility, then try again",
    ])
    exit(3)
}

do {
    try perform(args)
    writeJSON(["ok": true])
} catch {
    writeJSON(["ok": false, "error": "\(error)"])
    exit(1)
}
