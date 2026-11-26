import CoreBluetooth
import CryptoKit
import Foundation

/// iPhone side of the Bluetooth (text only) transport. Finds the Mac helper
/// ("WhisperBridge Bluetooth") by its service UUID, connects, writes framed
/// messages and waits for the matching `BLEAck`.
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
    /// Name the Mac helper advertises (e.g. "WhisperBridge Brandon's Air").
    @Published public private(set) var peerName: String?
    /// Recent link events for Settings → Bluetooth diagnostics. No text or tokens.
    @Published public private(set) var diagnostics: [String] = []

    /// Display name of the connected Mac, without the helper's prefix.
    public var macName: String {
        let raw = peerName ?? "Mac"
        return raw.hasPrefix("WhisperBridge ") ? String(raw.dropFirst("WhisperBridge ".count)) : raw
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var messageChar: CBCharacteristic?
    private var ackChar: CBCharacteristic?
    private var nextID: UInt16 = UInt16.random(in: 0...UInt16.max)
    private var ackKey: SymmetricKey?

    private var readyWaiters: [CheckedContinuation<String?, Never>] = []
    private var writeWaiter: CheckedContinuation<Error?, Never>?
    private var ackWaiters: [UInt16: CheckedContinuation<BLEAck?, Never>] = [:]
    private var busy = false
    private var readyGeneration = 0
    /// How far the current attempt got, for an honest timeout message.
    private enum Stage { case scanning, connecting, discovering, subscribing }
    private var stage: Stage = .scanning
    /// Connect attempts in this round; a stuck connect is cancelled and retried
    /// once with a freshly scanned peripheral.
    private var connectAttempts = 0
    private var lastError: String?

    private let serviceUUID = CBUUID(string: BLEProtocol.serviceUUID)
    private let messageUUID = CBUUID(string: BLEProtocol.messageCharacteristicUUID)
    private let ackUUID = CBUUID(string: BLEProtocol.ackCharacteristicUUID)
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
                      success: { _ in "Connected over Bluetooth" })
    }

    /// Starts looking for the Mac helper so the mode pill shows a live state
    /// before the first send. Silent: failures just leave it "Not connected".
    public func warmUp() {
        guard !busy, !connected, readyWaiters.isEmpty else { return }
        Task { _ = await ensureReady() }
    }

    public func clearDiagnostics() {
        diagnostics = []
        defaults.removeObject(forKey: Self.diagnosticsKey)
    }

    // MARK: - Flow

    private func perform(_ message: BLETextMessage, token: String,
                         success: (BLEAck) -> String) async -> BridgeClient.Result {
        if let reason = message.rejectionReason {
            return .init(ok: false, message: reason)
        }
        guard !busy else { return .init(ok: false, message: "Bluetooth is busy, try again") }
        busy = true
        defer { busy = false }

        if let problem = await ensureReady() {
            return .init(ok: false, message: problem)
        }
        guard let peripheral, let messageChar else {
            return .init(ok: false, message: "Mac helper not found")
        }
        let key = BLESecurity.key(token: token)
        guard let json = try? JSONEncoder().encode(message),
              let sealed = try? BLESecurity.seal(json, key: key, direction: .message) else {
            return .init(ok: false, message: "Could not encode message")
        }
        ackKey = key
        let id = nextID
        nextID &+= 1
        let maxWrite = min(peripheral.maximumWriteValueLength(for: .withResponse), 512)
        let frames: [Data]
        do {
            frames = try BLEFraming.frames(payload: sealed, messageID: id, maxWrite: maxWrite)
        } catch {
            return .init(ok: false, message: "Text too long for Bluetooth (max 64 KB)")
        }
        note("\(message.kind) \(id): \(sealed.count) bytes sealed in \(frames.count) frame(s) of ≤\(maxWrite)")

        for frame in frames {
            let error: Error? = await withCheckedContinuation { cont in
                writeWaiter = cont
                peripheral.writeValue(frame, for: messageChar, type: .withResponse)
            }
            if let error {
                note("write failed: \(Self.describe(error))")
                return .init(ok: false, message: "Bluetooth write failed — \(Self.describe(error))")
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

    /// Returns nil when connected with both characteristics ready, else a reason.
    private func ensureReady() async -> String? {
        if connected, messageChar != nil, peripheral?.state == .connected { return nil }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        let result: String? = await withCheckedContinuation { cont in
            readyWaiters.append(cont)
            guard readyWaiters.count == 1 else { return }
            stage = .scanning
            connectAttempts = 0
            lastError = nil
            armTimeout(seconds: 15)
            startIfPossible()
        }
        return result
    }

    private func armTimeout(seconds: Double) {
        readyGeneration += 1
        let generation = readyGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.readyGeneration == generation, !self.readyWaiters.isEmpty else { return }
            self.timedOut()
        }
    }

    private func timedOut() {
        note("timeout at stage \(stage) (attempt \(connectAttempts))")
        if stage == .connecting, connectAttempts < 2, let central {
            // A connect that never completes: drop it and try once more with a
            // fresh advertisement (the Mac rotates its private address).
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            stage = .scanning
            setStatus("Retrying…", connected: false)
            armTimeout(seconds: 12)
            central.scanForPeripherals(withServices: [serviceUUID],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            return
        }
        let detail = lastError.map { " (\($0))" } ?? ""
        let message: String
        switch stage {
        case .scanning:
            message = "Mac helper not found — open WhisperBridge Bluetooth on the Mac (menu bar) and keep Bluetooth on"
        case .connecting:
            message = "Found the Mac but couldn't connect\(detail) — see Settings → Bluetooth diagnostics"
        case .discovering:
            message = "Connected, but the helper didn't answer\(detail) — quit and reopen WhisperBridge Bluetooth on the Mac"
        case .subscribing:
            message = "Connected, but the helper didn't accept the link\(detail) — update WhisperBridge Bluetooth on the Mac"
        }
        if let peripheral, peripheral.state != .connected || messageChar == nil {
            central?.cancelPeripheralConnection(peripheral)   // start clean next time
        }
        finishReady(message)
    }

    private func startIfPossible() {
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            if let peripheral, peripheral.state == .connected {
                discover(on: peripheral)
            } else if let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first {
                // Already linked at the system level (same Apple ID / Continuity):
                // such peripherals don't show up in scans, so reuse the link.
                note("reusing system-connected \(Self.short(known.identifier))")
                peerName = peerName ?? known.name
                connect(known)
            } else {
                setStatus("Searching…", connected: false)
                note("scanning for helper service")
                central.scanForPeripherals(withServices: [serviceUUID])
            }
        case .unauthorized:
            note("central unauthorized")
            finishReady("Allow Bluetooth for Whisper Bridge in Settings → Privacy & Security → Bluetooth")
        case .poweredOff:
            finishReady("Turn Bluetooth on")
        case .unsupported:
            finishReady("Bluetooth isn't available on this device")
        default:
            break // wait for centralManagerDidUpdateState
        }
    }

    private func connect(_ p: CBPeripheral) {
        if let old = peripheral, old.identifier != p.identifier, old.state != .disconnected {
            central?.cancelPeripheralConnection(old)
        }
        peripheral = p
        p.delegate = self
        stage = .connecting
        connectAttempts += 1
        setStatus(connectAttempts > 1 ? "Connecting (retry)…" : "Connecting…", connected: false)
        note("connect \(Self.short(p.identifier)) attempt \(connectAttempts), state \(p.state.rawValue)")
        if p.state == .connected {
            discover(on: p)
        } else {
            armTimeout(seconds: 8)
            central?.connect(p)
        }
    }

    private func discover(on p: CBPeripheral) {
        stage = .discovering
        setStatus("Finding the helper…", connected: false)
        armTimeout(seconds: 10)
        p.discoverServices([serviceUUID])
    }

    private func finishReady(_ problem: String?) {
        guard !readyWaiters.isEmpty else { return }
        readyGeneration += 1
        let waiters = readyWaiters
        readyWaiters.removeAll()
        if let problem {
            central?.stopScan()
            note("not ready: \(problem)")
            if !connected { setStatus("Not connected", connected: false) }
        }
        waiters.forEach { $0.resume(returning: problem) }
    }

    private func resolveAck(_ id: UInt16, _ ack: BLEAck?) {
        ackWaiters.removeValue(forKey: id)?.resume(returning: ack)
    }

    private func setStatus(_ text: String, connected: Bool) {
        status = text
        self.connected = connected
        phase = connected ? .connected : (readyWaiters.isEmpty ? .idle : .searching)
    }

    private func dropLink(_ reason: String) {
        messageChar = nil
        ackChar = nil
        setStatus(reason, connected: false)
        writeWaiter?.resume(returning: NSError(domain: "WhisperBridge", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: reason]))
        writeWaiter = nil
        for id in Array(ackWaiters.keys) { resolveAck(id, nil) }
    }

    /// Accepts sealed acks; unsealed ones only when they report a failure (the
    /// Mac sends those when it can't open our message, e.g. a wrong pairing).
    private func decodeAck(_ data: Data) -> BLEAck? {
        if let key = ackKey, let plain = try? BLESecurity.open(data, key: key, direction: .ack),
           let ack = try? JSONDecoder().decode(BLEAck.self, from: plain) {
            return ack
        }
        if let ack = try? JSONDecoder().decode(BLEAck.self, from: data), !ack.ok { return ack }
        return nil
    }

    // MARK: - Diagnostics

    private func note(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        diagnostics.append("\(stamp) \(line)")
        if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
        defaults.set(diagnostics, forKey: Self.diagnosticsKey)
    }

    /// "CBErrorDomain 14: Peer removed pairing information" style detail.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let domain = ns.domain == CBError.errorDomain ? "CBError"
            : ns.domain == CBATTError.errorDomain ? "CBATTError" : ns.domain
        return "\(domain) \(ns.code): \(ns.localizedDescription)"
    }

    nonisolated static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}

extension BluetoothBridge: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            note("central state \(central.state.rawValue) (authorization \(CBManager.authorization.rawValue))")
            if central.state != .poweredOn { dropLink("Bluetooth unavailable") }
            if !readyWaiters.isEmpty { startIfPossible() }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        MainActor.assumeIsolated {
            guard stage == .scanning else { return }
            central.stopScan()
            note("found \(Self.short(peripheral.identifier)) \"\(advertisedName ?? peripheral.name ?? "?")\" RSSI \(RSSI) connectable \(connectable.map(String.init) ?? "?")")
            peerName = advertisedName ?? peripheral.name
            connect(peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            note("connected \(Self.short(peripheral.identifier)), max write \(peripheral.maximumWriteValueLength(for: .withResponse))")
            peripheral.delegate = self
            discover(on: peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        let detail = error.map(Self.describe) ?? "no error given"
        MainActor.assumeIsolated {
            note("didFailToConnect: \(detail)")
            lastError = detail
            dropLink("Couldn't connect")
            if connectAttempts < 2, !readyWaiters.isEmpty {
                stage = .connecting
                timedOut()   // retries once with a fresh scan
            } else {
                finishReady("Couldn't connect to the Mac helper — \(detail)")
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
        let detail = error.map(Self.describe)
        MainActor.assumeIsolated {
            note("disconnected \(Self.short(peripheral.identifier))\(detail.map { ": \($0)" } ?? "")")
            if let detail { lastError = detail }
            dropLink(detail.map { "Disconnected — \($0)" } ?? "Disconnected")
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let detail = error.map(Self.describe)
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                note("service missing (\(peripheral.services?.count ?? 0) services)\(detail.map { ": \($0)" } ?? "")")
                finishReady("Mac helper service missing\(detail.map { " — \($0)" } ?? "") — reopen WhisperBridge Bluetooth on the Mac")
                return
            }
            peripheral.discoverCharacteristics([messageUUID, ackUUID], for: service)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                       error: Error?) {
        MainActor.assumeIsolated {
            messageChar = service.characteristics?.first { $0.uuid == messageUUID }
            ackChar = service.characteristics?.first { $0.uuid == ackUUID }
            guard messageChar != nil, let ackChar else {
                note("characteristics missing\(error.map { ": \(Self.describe($0))" } ?? "")")
                finishReady("Mac helper characteristics missing — update WhisperBridge Bluetooth on the Mac")
                return
            }
            stage = .subscribing
            setStatus("Opening the link…", connected: false)
            armTimeout(seconds: 15)
            peripheral.setNotifyValue(true, for: ackChar)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let detail = error.map(Self.describe)
        MainActor.assumeIsolated {
            if let detail {
                note("subscribe failed: \(detail)")
                lastError = detail
                finishReady("Couldn't open the link — \(detail). If it mentions encryption, update WhisperBridge Bluetooth on the Mac.")
                return
            }
            note("link ready")
            if peerName == nil { peerName = peripheral.name }
            setStatus("Connected to \(macName)", connected: true)
            finishReady(nil)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            writeWaiter?.resume(returning: error)
            writeWaiter = nil
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let data = characteristic.value
        let isAck = characteristic.uuid == CBUUID(string: BLEProtocol.ackCharacteristicUUID)
        MainActor.assumeIsolated {
            guard isAck, let data else { return }
            guard let ack = decodeAck(data) else {
                note("ack ignored: couldn't verify (\(data.count) bytes)")
                return
            }
            resolveAck(ack.id, ack)
        }
    }
}
