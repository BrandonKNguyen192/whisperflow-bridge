import CoreBluetooth
import CryptoKit
import Foundation

/// iPhone side of the Bluetooth (text only) transport.
///
/// The iPhone is the Bluetooth **peripheral**: while the app is open it
/// advertises the WhisperBridge service, and the Mac helper ("WhisperBridge
/// Bluetooth", a central) finds it, connects and subscribes. Messages go out as
/// notifications on the message characteristic; the Mac writes acks back.
/// (The first design had the iPhone connect to the Mac; those connects hung
/// between same-Apple-ID devices, so the roles were swapped.)
///
/// Security is at the app layer (`BLESecurity`): every message is sealed with
/// AES-GCM using a key derived from the receiver token from the pairing QR, so
/// no OS Bluetooth pairing prompt is involved and the token never crosses the air.
@MainActor
public final class BluetoothBridge: NSObject, ObservableObject {
    public static let shared = BluetoothBridge()

    @Published public private(set) var status = "Not connected"
    @Published public private(set) var connected = false
    /// Coarse link state for the always-visible mode pill.
    public enum Phase: Equatable { case idle, searching, connected }
    @Published public private(set) var phase: Phase = .idle
    /// The Mac's name, from its sealed hello after it connects.
    @Published public private(set) var peerName: String?
    /// True when the connected Mac's hello couldn't be opened with this profile's token.
    @Published public private(set) var pairingMismatch = false
    /// Recent link events for Settings → Bluetooth diagnostics. No text or tokens.
    @Published public private(set) var diagnostics: [String] = []

    public var macName: String { peerName ?? "Mac" }

    private var manager: CBPeripheralManager?
    private var messageChar: CBMutableCharacteristic?
    private var ackChar: CBMutableCharacteristic?
    private var serviceAdded = false
    private var subscriber: CBCentral?
    private var key: SymmetricKey?
    private var nextID: UInt16 = UInt16.random(in: 1...UInt16.max)

    private var linkWaiters: [CheckedContinuation<Bool, Never>] = []
    private var readyToSendWaiter: CheckedContinuation<Bool, Never>?
    private var ackWaiters: [UInt16: CheckedContinuation<BLEAck?, Never>] = [:]
    private var busy = false

    private let serviceUUID = CBUUID(string: BLEProtocol.serviceUUID)
    private let defaults = UserDefaults.standard
    private static let diagnosticsKey = "bluetooth_diagnostics"

    public override init() {
        super.init()
        diagnostics = defaults.stringArray(forKey: Self.diagnosticsKey) ?? []
    }

    // MARK: - Public API

    public func send(text: String, mode: String, enterAfter: Bool, token: String) async -> BridgeClient.Result {
        await perform(BLETextMessage(kind: "send", text: text, mode: mode, enterAfter: enterAfter), token: token,
                      success: { ack in ack.message.isEmpty ? "Sent over Bluetooth" : ack.message })
    }

    /// Like the Wi-Fi Test button: checks the Mac helper and the token without typing.
    public func probe(token: String) async -> BridgeClient.Result {
        await perform(BLETextMessage(kind: "probe", text: "", mode: "type"), token: token,
                      success: { _ in "Connected over Bluetooth to \(self.macName)" })
    }

    /// Starts advertising so the Mac helper can connect and the mode pill shows
    /// a live state before the first send.
    public func warmUp(token: String) {
        key = BLESecurity.key(token: token)
        start()
    }

    /// Stops advertising and drops the link (e.g. when a Wi-Fi profile is active).
    public func stop() {
        guard let manager else { return }
        manager.stopAdvertising()
        if serviceAdded { manager.removeAllServices() }
        serviceAdded = false
        subscriber = nil
        failPending("Bluetooth stopped")
        setStatus("Not connected", connected: false, waiting: false)
        note("stopped advertising")
    }

    public func clearDiagnostics() {
        diagnostics = []
        defaults.removeObject(forKey: Self.diagnosticsKey)
    }

    // MARK: - Flow

    private func start() {
        if manager == nil {
            note("starting peripheral")
            manager = CBPeripheralManager(delegate: self, queue: .main)
        } else if let manager, manager.state == .poweredOn, !manager.isAdvertising, subscriber == nil {
            publish()
        }
    }

    private func perform(_ message: BLETextMessage, token: String,
                         success: @escaping (BLEAck) -> String) async -> BridgeClient.Result {
        if let reason = message.rejectionReason {
            return .init(ok: false, message: reason)
        }
        guard !busy else { return .init(ok: false, message: "Bluetooth is busy, try again") }
        busy = true
        defer { busy = false }

        key = BLESecurity.key(token: token)
        start()
        if let problem = stateProblem() { return .init(ok: false, message: problem) }
        if subscriber == nil {
            setStatus("Waiting for the Mac…", connected: false, waiting: true)
            let linked: Bool = await withCheckedContinuation { cont in
                linkWaiters.append(cont)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    self?.finishLinkWait(false)
                }
            }
            guard linked, subscriber != nil else {
                if let problem = stateProblem() { return .init(ok: false, message: problem) }
                setStatus("Waiting for the Mac…", connected: false, waiting: false)
                note("\(message.kind): Mac never connected within 20 s")
                return .init(ok: false, message:
                    "The Mac hasn't connected — open WhisperBridge Bluetooth on the Mac (menu bar), keep this screen open and the Mac within a few metres")
            }
        }
        guard let manager, let messageChar, let central = subscriber, let key else {
            return .init(ok: false, message: "Mac helper not connected")
        }
        if pairingMismatch {
            return .init(ok: false, message: "This Mac's pairing doesn't match — on the Mac open Pair iPhone… and scan the QR again")
        }

        guard let json = try? JSONEncoder().encode(message),
              let sealed = try? BLESecurity.seal(json, key: key, direction: .message) else {
            return .init(ok: false, message: "Could not encode message")
        }
        let id = nextID
        nextID = nextID == UInt16.max ? 1 : nextID + 1   // 0 is the Mac's hello
        let maxChunk = min(central.maximumUpdateValueLength, 512)
        let frames: [Data]
        do {
            frames = try BLEFraming.frames(payload: sealed, messageID: id, maxWrite: maxChunk)
        } catch {
            return .init(ok: false, message: "Text too long for Bluetooth (max 64 KB)")
        }
        note("\(message.kind) \(id): \(sealed.count) bytes sealed in \(frames.count) frame(s) of ≤\(maxChunk)")

        for frame in frames {
            while !manager.updateValue(frame, for: messageChar, onSubscribedCentrals: [central]) {
                // Transmit queue full: wait for peripheralManagerIsReady.
                let ready: Bool = await withCheckedContinuation { cont in
                    readyToSendWaiter = cont
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        self?.resumeReadyToSend(false)
                    }
                }
                guard ready, subscriber != nil else {
                    note("\(message.kind) \(id): link dropped while sending")
                    return .init(ok: false, message: "Bluetooth link dropped while sending — try again")
                }
            }
        }

        let ack: BLEAck? = await withCheckedContinuation { cont in
            ackWaiters[id] = cont
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.resolveAck(id, nil)
            }
        }
        guard let ack else {
            note("\(message.kind) \(id): no ack within 15 s")
            return .init(ok: false, message: "No answer from the Mac helper — update it to the latest build")
        }
        note("\(message.kind) \(id): ack ok=\(ack.ok)")
        return ack.ok ? .init(ok: true, message: success(ack)) : .init(ok: false, message: ack.message)
    }

    private func stateProblem() -> String? {
        guard let manager else { return nil }
        switch manager.state {
        case .unauthorized: return "Allow Bluetooth for Whisper Bridge in Settings → Privacy & Security → Bluetooth"
        case .poweredOff: return "Turn Bluetooth on"
        case .unsupported: return "Bluetooth isn't available on this device"
        default: return nil
        }
    }

    private func publish() {
        guard let manager else { return }
        if !serviceAdded {
            let message = CBMutableCharacteristic(
                type: CBUUID(string: BLEProtocol.messageCharacteristicUUID),
                properties: [.notify], value: nil, permissions: [.readable])
            let ack = CBMutableCharacteristic(
                type: CBUUID(string: BLEProtocol.ackCharacteristicUUID),
                properties: [.write], value: nil, permissions: [.writeable])
            let service = CBMutableService(type: serviceUUID, primary: true)
            service.characteristics = [message, ack]
            messageChar = message
            ackChar = ack
            manager.removeAllServices()
            manager.add(service)
            return   // advertising starts in didAdd
        }
        advertise()
    }

    private func advertise() {
        guard let manager, !manager.isAdvertising else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "WhisperBridge iPhone",
        ])
    }

    private func finishLinkWait(_ ok: Bool) {
        let waiters = linkWaiters
        linkWaiters.removeAll()
        waiters.forEach { $0.resume(returning: ok) }
    }

    private func resumeReadyToSend(_ ok: Bool) {
        readyToSendWaiter?.resume(returning: ok)
        readyToSendWaiter = nil
    }

    private func resolveAck(_ id: UInt16, _ ack: BLEAck?) {
        ackWaiters.removeValue(forKey: id)?.resume(returning: ack)
    }

    private func failPending(_ reason: String) {
        finishLinkWait(false)
        resumeReadyToSend(false)
        for id in Array(ackWaiters.keys) { resolveAck(id, nil) }
    }

    private func setStatus(_ text: String, connected: Bool, waiting: Bool) {
        status = text
        self.connected = connected
        phase = connected ? .connected : (waiting ? .searching : .idle)
    }

    /// Sealed acks are trusted; unsealed ones only when they report a failure
    /// (the Mac sends those when it can't open our message, e.g. wrong pairing).
    private func handleAckWrite(_ data: Data) {
        if let key, let plain = try? BLESecurity.open(data, key: key, direction: .ack),
           let ack = try? JSONDecoder().decode(BLEAck.self, from: plain) {
            if ack.isHello {
                peerName = ack.mac
                pairingMismatch = false
                note("hello from \"\(ack.mac ?? "?")\" — pairing OK")
                setStatus("Connected to \(macName)", connected: true, waiting: false)
            } else {
                resolveAck(ack.id, ack)
            }
            return
        }
        if let ack = try? JSONDecoder().decode(BLEAck.self, from: data), !ack.ok {
            resolveAck(ack.id, ack)
            return
        }
        // Sealed with a different token: this profile isn't paired with that Mac.
        pairingMismatch = true
        note("ack/hello couldn't be opened (\(data.count) bytes) — pairing mismatch")
        setStatus("Connected, but pairing doesn't match — scan the Mac's QR", connected: true, waiting: false)
    }

    // MARK: - Diagnostics

    private func note(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        diagnostics.append("\(stamp) \(line)")
        if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
        defaults.set(diagnostics, forKey: Self.diagnosticsKey)
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let domain = ns.domain == CBError.errorDomain ? "CBError"
            : ns.domain == CBATTError.errorDomain ? "CBATTError" : ns.domain
        return "\(domain) \(ns.code): \(ns.localizedDescription)"
    }

    nonisolated static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}

extension BluetoothBridge: CBPeripheralManagerDelegate {
    nonisolated public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            note("peripheral state \(peripheral.state.rawValue) (authorization \(CBManager.authorization.rawValue))")
            if peripheral.state == .poweredOn {
                setStatus("Waiting for the Mac…", connected: false, waiting: true)
                publish()
            } else {
                serviceAdded = false
                subscriber = nil
                failPending("Bluetooth unavailable")
                setStatus(stateProblem() ?? "Bluetooth unavailable", connected: false, waiting: false)
            }
        }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        let detail = error.map(Self.describe)
        MainActor.assumeIsolated {
            if let detail {
                note("add service failed: \(detail)")
                setStatus("Bluetooth setup failed — \(detail)", connected: false, waiting: false)
                return
            }
            serviceAdded = true
            note("service added")
            advertise()
        }
    }

    nonisolated public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let detail = error.map(Self.describe)
        MainActor.assumeIsolated {
            if let detail {
                note("advertising failed: \(detail)")
                setStatus("Advertising failed — \(detail)", connected: false, waiting: false)
            } else {
                note("advertising (waiting for the Mac helper)")
                if subscriber == nil { setStatus("Waiting for the Mac…", connected: false, waiting: true) }
            }
        }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                              didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscriber = central
            note("Mac \(Self.short(central.identifier)) subscribed (max update \(central.maximumUpdateValueLength) bytes)")
            setStatus("Connected to \(macName)", connected: true, waiting: false)
            finishLinkWait(true)
        }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                              didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            note("Mac \(Self.short(central.identifier)) unsubscribed / disconnected")
            if subscriber?.identifier == central.identifier { subscriber = nil }
            failPending("Mac disconnected")
            setStatus("Waiting for the Mac…", connected: false, waiting: true)
            advertise()
        }
    }

    nonisolated public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { resumeReadyToSend(true) }
    }

    nonisolated public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let writes = requests.map { ($0.characteristic.uuid, $0.value) }
        MainActor.assumeIsolated {
            for (uuid, value) in writes where uuid == CBUUID(string: BLEProtocol.ackCharacteristicUUID) {
                if let value { handleAckWrite(value) }
            }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }
}
