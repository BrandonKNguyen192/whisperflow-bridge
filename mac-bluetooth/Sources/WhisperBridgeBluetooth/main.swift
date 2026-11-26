import AppKit
import BridgeBLECore
import CoreBluetooth

/// WhisperBridge Bluetooth — a tiny menu bar app that lets the iPhone send
/// text to this Mac over Bluetooth LE when there is no shared network (for
/// example on a plane). Text only: trackpad and air mouse stay on Wi-Fi.
/// Every message is handed to the normal Whisper Bridge receiver on
/// 127.0.0.1:9877, which does the typing and checks the token.
final class BluetoothHelper: NSObject, NSApplicationDelegate, CBPeripheralManagerDelegate {
    private var statusItem: NSStatusItem!
    private var statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var lastLine = NSMenuItem(title: "No messages yet", action: nil, keyEquivalent: "")

    private var manager: CBPeripheralManager!
    private var ackChar: CBMutableCharacteristic!
    private var reassembler = BLEReassembler()
    private var pendingAcks: [(Data, CBCentral?)] = []
    private var subscribers = 0
    private let forwarder = ReceiverForwarder(
        port: UserDefaults.standard.integer(forKey: "receiverPort").nonZero ?? 9877)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                           accessibilityDescription: "WhisperBridge Bluetooth")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "WhisperBridge Bluetooth (text only)", action: nil, keyEquivalent: ""))
        menu.addItem(statusLine)
        menu.addItem(lastLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        NSLog("WhisperBridge Bluetooth: %@", text)
    }

    // MARK: - Peripheral

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publish()
        case .unauthorized:
            setStatus("Allow Bluetooth in System Settings → Privacy & Security → Bluetooth")
        case .poweredOff:
            setStatus("Bluetooth is off")
        default:
            setStatus("Bluetooth unavailable")
        }
    }

    private func publish() {
        let message = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.messageCharacteristicUUID),
            properties: [.write],
            value: nil,
            permissions: [.writeEncryptionRequired])   // forces Bluetooth pairing before any text arrives
        ackChar = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.ackCharacteristicUUID),
            properties: [.notify],
            value: nil,
            permissions: [.readEncryptionRequired])
        let service = CBMutableService(type: CBUUID(string: BLEProtocol.serviceUUID), primary: true)
        service.characteristics = [message, ackChar]
        manager.removeAllServices()
        manager.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { setStatus("Bluetooth setup failed: \(error.localizedDescription)"); return }
        let name = "WhisperBridge \(Host.current().localizedName ?? "Mac")".prefix(28)
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEProtocol.serviceUUID)],
            CBAdvertisementDataLocalNameKey: String(name),
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        setStatus(error.map { "Advertising failed: \($0.localizedDescription)" } ?? "Waiting for iPhone…")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        subscribers += 1
        peripheral.setDesiredConnectionLatency(.low, for: central)
        setStatus("iPhone connected")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers = max(0, subscribers - 1)
        if subscribers == 0 { setStatus("Waiting for iPhone…") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        reassembler.expire(now: Date())   // drop half-sent messages older than the timeout
        for request in requests {
            guard request.characteristic.uuid == CBUUID(string: BLEProtocol.messageCharacteristicUUID),
                  let value = request.value else {
                peripheral.respond(to: requests[0], withResult: .requestNotSupported)
                return
            }
            switch reassembler.add(value) {
            case .incomplete:
                break
            case .complete(let id, let payload):
                handle(id: id, payload: payload, from: request.central)
            case .rejected(let id, let reason):
                if let id { sendAck(BLEAck(id: id, ok: false, message: reason), to: request.central) }
            }
        }
        peripheral.respond(to: requests[0], withResult: .success)
    }

    private func handle(id: UInt16, payload: Data, from central: CBCentral) {
        let isProbe = ReceiverForwarder.isProbe(payload)
        switch forwarder.decide(payload: payload) {
        case .refuse(let reason):
            sendAck(BLEAck(id: id, ok: false, message: reason), to: central)
        case .forward(let request):
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode
                let ack = ReceiverForwarder.ack(id: id, isProbe: isProbe, status: status, body: data,
                                                error: error?.localizedDescription)
                DispatchQueue.main.async {
                    if !isProbe {
                        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                        self?.lastLine.title = "\(time): \(ack.message)"
                    }
                    self?.sendAck(ack, to: central)
                }
            }.resume()
        }
    }

    private func sendAck(_ ack: BLEAck, to central: CBCentral?) {
        guard let data = try? JSONEncoder().encode(ack) else { return }
        let targets = central.map { [$0] }
        if !manager.updateValue(data, for: ackChar, onSubscribedCentrals: targets) {
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

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

let app = NSApplication.shared
let helper = BluetoothHelper()
app.delegate = helper
app.setActivationPolicy(.accessory)
app.run()
