import AppKit
import BridgeBLECore
import CoreBluetooth
import CoreImage

/// WhisperBridge Bluetooth — a tiny menu bar app that lets the iPhone send
/// text to this Mac over Bluetooth LE when there is no shared network (for
/// example on a plane). Text only: trackpad and air mouse stay on Wi-Fi.
/// Every message is handed to the normal Whisper Bridge receiver on
/// 127.0.0.1:9877, which does the typing and checks the token.
final class BluetoothHelper: NSObject, NSApplicationDelegate, NSMenuDelegate, CBPeripheralManagerDelegate {
    private enum RadioState: Equatable {
        case starting, unauthorized, poweredOff, unsupported, advertising, failed(String)
    }

    private var statusItem: NSStatusItem!
    private let stateLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let iphoneLine = NSMenuItem(title: "iPhone: not connected", action: nil, keyEquivalent: "")
    private let receiverLine = NSMenuItem(title: "Receiver: checking…", action: nil, keyEquivalent: "")
    private let lastLine = NSMenuItem(title: "Last message: none yet", action: nil, keyEquivalent: "")
    private let privacyItem = NSMenuItem(title: "Open Bluetooth Privacy Settings…",
                                         action: #selector(openPrivacy), keyEquivalent: "")
    private var pairWindow: NSWindow?

    private var manager: CBPeripheralManager!
    private var ackChar: CBMutableCharacteristic!
    private var reassembler = BLEReassembler()
    private var replay = BLEReplayGuard()
    private var pendingAcks: [(Data, CBCentral?)] = []
    private var subscribers = Set<UUID>()
    private var radio: RadioState = .starting { didSet { refresh() } }
    private var receiverUp: Bool? { didSet { refresh() } }
    private var lastMessage: (Date, String)? { didSet { refresh() } }
    private var receiverTimer: Timer?

    private let port = UserDefaults.standard.integer(forKey: "receiverPort").nonZero ?? 9877
    private lazy var forwarder = ReceiverForwarder(port: port)
    private var macName: String { Host.current().localizedName ?? "Mac" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "WhisperBridge Bluetooth (text only)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for item in [stateLine, iphoneLine, receiverLine, lastLine] {
            item.isEnabled = false
            menu.addItem(item)
        }
        privacyItem.target = self
        menu.addItem(privacyItem)
        menu.addItem(.separator())
        let pair = NSMenuItem(title: "Pair iPhone…", action: #selector(showPairWindow), keyEquivalent: "p")
        pair.target = self
        menu.addItem(pair)
        let logItem = NSMenuItem(title: "Show Log", action: #selector(showLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refresh()
        Log.write("launched v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") on \(macName), receiver port \(port), token file \(PairingLink.readToken().isEmpty ? "MISSING" : "present")")

        manager = CBPeripheralManager(delegate: self, queue: .main)
        checkReceiver()
        receiverTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkReceiver()
        }
    }

    func menuWillOpen(_ menu: NSMenu) { checkReceiver() }

    // MARK: - Status display

    private func refresh() {
        guard statusItem != nil else { return }
        let symbol: String
        switch radio {
        case .starting:     stateLine.title = "Bluetooth: starting…"; symbol = "antenna.radiowaves.left.and.right"
        case .unauthorized: stateLine.title = "⚠️ Bluetooth permission needed — click below to allow"
                            symbol = "exclamationmark.triangle"
        case .poweredOff:   stateLine.title = "⚠️ Bluetooth is off"; symbol = "antenna.radiowaves.left.and.right.slash"
        case .unsupported:  stateLine.title = "⚠️ Bluetooth LE not available"; symbol = "antenna.radiowaves.left.and.right.slash"
        case .failed(let why): stateLine.title = "⚠️ \(why)"; symbol = "exclamationmark.triangle"
        case .advertising:
            stateLine.title = "Bluetooth: ready — visible as “WhisperBridge \(macName)”"
            symbol = subscribers.isEmpty ? "antenna.radiowaves.left.and.right" : "iphone.radiowaves.left.and.right"
        }
        privacyItem.isHidden = radio != .unauthorized
        iphoneLine.title = subscribers.isEmpty
            ? "iPhone: not connected"
            : (subscribers.count == 1 ? "iPhone: connected" : "iPhones: \(subscribers.count) connected")
        switch receiverUp {
        case .none:        receiverLine.title = "Receiver (port \(port)): checking…"
        case .some(true):  receiverLine.title = "Receiver (port \(port)): reachable ✓"
        case .some(false): receiverLine.title = "⚠️ Receiver (port \(port)): not running — start Whisper Bridge"
        }
        if let (date, text) = lastMessage {
            let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
            lastLine.title = "Last message \(time): \(text)"
        } else {
            lastLine.title = "Last message: none yet"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "WhisperBridge Bluetooth")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = radio != .advertising
        statusItem.button?.toolTip = [stateLine.title, iphoneLine.title, receiverLine.title].joined(separator: "\n")
    }

    private func checkReceiver() {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!, timeoutInterval: 3)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let up = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                if self?.receiverUp != up { Log.write("receiver /health: \(up ? "up" : "DOWN")") }
                self?.receiverUp = up
            }
        }.resume()
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func openPrivacy() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pair window

    @objc private func showPairWindow() {
        pairWindow?.close()
        // Token is read fresh, kept only in this window's memory, never logged.
        let token = PairingLink.readToken()
        let link = PairingLink.bluetooth(token: token, macName: macName, port: port)

        let qr = NSImageView(image: Self.qrImage(link, side: 280) ?? NSImage())
        qr.imageScaling = .scaleNone
        let heading = NSTextField(labelWithString: "Pair iPhone over Bluetooth")
        heading.font = .boldSystemFont(ofSize: 15)
        let steps = NSTextField(wrappingLabelWithString:
            "On the iPhone: Whisper Bridge → Settings → Scan, and point at this code.\n" +
            "It creates “\(macName) · Bluetooth” and switches to it. Then tap Test and accept " +
            "the Bluetooth pairing prompt on both devices.")
        steps.preferredMaxLayoutWidth = 300
        let warning = NSTextField(wrappingLabelWithString: token.isEmpty
            ? "⚠️ No receiver token found at \(PairingLink.tokenPath). The link has no token, so sending only works if the receiver doesn't require one."
            : "This code contains your receiver token. Don't share it.")
        warning.preferredMaxLayoutWidth = 300
        warning.textColor = .secondaryLabelColor
        warning.font = .systemFont(ofSize: 11)
        let copy = NSButton(title: "Copy link", target: nil, action: nil)
        let copied = NSTextField(labelWithString: "")
        copied.textColor = .secondaryLabelColor
        copy.target = PairCopyTarget.shared
        copy.action = #selector(PairCopyTarget.copy(_:))
        PairCopyTarget.shared.link = link
        PairCopyTarget.shared.feedback = copied

        let buttons = NSStackView(views: [copy, copied])
        let stack = NSStackView(views: [heading, qr, steps, warning, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pair iPhone"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.delegate = PairCopyTarget.shared   // forget the link when closed
        window.center()
        pairWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func qrImage(_ text: String, side: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = floor(side / output.extent.width)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Peripheral

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let names: [CBManagerState: String] = [.unknown: "unknown", .resetting: "resetting", .unsupported: "unsupported",
                                               .unauthorized: "UNAUTHORIZED", .poweredOff: "poweredOff", .poweredOn: "poweredOn"]
        Log.write("bluetooth state: \(names[peripheral.state] ?? "\(peripheral.state.rawValue)") (authorization \(CBManager.authorization.rawValue))")
        switch peripheral.state {
        case .poweredOn:
            publish()
        case .unauthorized:
            radio = .unauthorized
        case .poweredOff:
            radio = .poweredOff
        case .unsupported:
            radio = .unsupported
        default:
            radio = .starting
        }
        if peripheral.state != .poweredOn { subscribers.removeAll(); refresh() }
    }

    private func publish() {
        let message = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.messageCharacteristicUUID),
            properties: [.write],
            value: nil,
            // Open at the GATT level: messages are sealed with BLESecurity (key from the
            // receiver token), so no OS pairing prompt is needed between the iPhone and Mac.
            permissions: [.writeable])
        ackChar = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.ackCharacteristicUUID),
            properties: [.notify],
            value: nil,
            permissions: [.readable])
        let service = CBMutableService(type: CBUUID(string: BLEProtocol.serviceUUID), primary: true)
        service.characteristics = [message, ackChar]
        manager.removeAllServices()
        manager.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            Log.write("add service FAILED: \(Log.describe(error))")
            radio = .failed("Bluetooth setup failed: \(error.localizedDescription)")
            return
        }
        Log.write("service added")
        let name = "WhisperBridge \(macName)".prefix(28)
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEProtocol.serviceUUID)],
            CBAdvertisementDataLocalNameKey: String(name),
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            Log.write("advertising FAILED: \(Log.describe(error))")
            radio = .failed("Advertising failed: \(error.localizedDescription)")
        } else {
            Log.write("advertising as \"WhisperBridge \(macName)\"")
            radio = .advertising
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.insert(central.identifier)
        Log.write("central \(central.identifier.uuidString.prefix(8)) subscribed (max update \(central.maximumUpdateValueLength) bytes); \(subscribers.count) connected")
        peripheral.setDesiredConnectionLatency(.low, for: central)
        refresh()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.remove(central.identifier)
        Log.write("central \(central.identifier.uuidString.prefix(8)) unsubscribed; \(subscribers.count) connected")
        refresh()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        reassembler.expire(now: Date())   // drop half-sent messages older than the timeout
        let bytes = requests.reduce(0) { $0 + ($1.value?.count ?? 0) }
        Log.write("write: \(requests.count) request(s), \(bytes) bytes from \(requests[0].central.identifier.uuidString.prefix(8))")
        for request in requests {
            guard request.characteristic.uuid == CBUUID(string: BLEProtocol.messageCharacteristicUUID),
                  let value = request.value else {
                Log.write("write REFUSED: unexpected characteristic \(request.characteristic.uuid)")
                peripheral.respond(to: requests[0], withResult: .requestNotSupported)
                return
            }
            switch reassembler.add(value) {
            case .incomplete:
                break
            case .complete(let id, let payload):
                Log.write("message \(id) complete: \(payload.count) bytes sealed")
                handle(id: id, payload: payload, from: request.central)
            case .rejected(let id, let reason):
                Log.write("message \(id.map(String.init) ?? "?") rejected by framing: \(reason)")
                if let id { sendAck(BLEAck(id: id, ok: false, message: reason), to: request.central, sealed: false) }
            }
        }
        peripheral.respond(to: requests[0], withResult: .success)
    }

    private func handle(id: UInt16, payload: Data, from central: CBCentral) {
        // Read per message so a re-paired or rotated receiver token applies at once.
        let token = PairingLink.readToken()
        switch forwarder.decide(sealed: payload, token: token, replay: &replay) {
        case .refuse(let reason):
            Log.write("message \(id) refused: \(reason)")
            lastMessage = (Date(), "refused — \(reason)")
            // Plain (unsealed) error ack: the iPhone may hold the wrong key. It only
            // accepts unsealed acks that report failure, so this can't fake "Sent".
            sendAck(BLEAck(id: id, ok: false, message: reason), to: central, sealed: false)
        case .forward(let request, let isProbe):
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode
                let ack = ReceiverForwarder.ack(id: id, isProbe: isProbe, status: status, body: data,
                                                error: error?.localizedDescription)
                DispatchQueue.main.async {
                    guard let self else { return }
                    Log.write("message \(id) \(isProbe ? "probe" : "send") → receiver HTTP \(status.map(String.init) ?? "no answer (\(error?.localizedDescription ?? "?"))") → ack ok=\(ack.ok)")
                    self.receiverUp = status != nil
                    self.lastMessage = (Date(), isProbe ? "Test from iPhone — \(ack.message)" : ack.message)
                    self.sendAck(ack, to: central, sealed: true, token: token)
                }
            }.resume()
        }
    }

    private func sendAck(_ ack: BLEAck, to central: CBCentral?, sealed: Bool, token: String = "") {
        let data = sealed ? ReceiverForwarder.seal(ack, token: token) : try? JSONEncoder().encode(ack)
        guard let data else { return }
        let targets = central.map { [$0] }
        if !manager.updateValue(data, for: ackChar, onSubscribedCentrals: targets) {
            Log.write("ack \(ack.id) queued (transmit queue full)", verbose: true)
            pendingAcks.append((data, central))   // queue full; retried when ready
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        while let (data, central) = pendingAcks.first {
            guard peripheral.updateValue(data, for: ackChar, onSubscribedCentrals: central.map { [$0] }) else { return }
            pendingAcks.removeFirst()
        }
    }
}

/// Append-only diagnostics log at ~/Library/Logs/WhisperBridgeBluetooth.log.
/// State transitions, connections, sizes and HTTP statuses only: never the
/// token or message text. Rotates at 1 MB (one previous file kept).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WhisperBridgeBluetooth.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static var verboseEnabled = UserDefaults.standard.bool(forKey: "verboseLog")

    static func write(_ line: String, verbose: Bool = false) {
        if verbose && !verboseEnabled { return }
        let entry = "\(formatter.string(from: Date())) \(line)\n"
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(entry.utf8))
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}

/// Copy button target; also drops the link (and token) when the window closes.
final class PairCopyTarget: NSObject, NSWindowDelegate {
    static let shared = PairCopyTarget()
    var link = ""
    weak var feedback: NSTextField?

    @objc func copy(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        feedback?.stringValue = "Copied — paste it in Settings → Paste pairing link"
    }

    func windowWillClose(_ notification: Notification) {
        link = ""
        (notification.object as? NSWindow)?.contentView = nil
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

let app = NSApplication.shared
let helper = BluetoothHelper()
app.delegate = helper
app.setActivationPolicy(.accessory)
app.run()
