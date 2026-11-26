import CoreBluetooth
import Foundation

/// iPhone side of the Bluetooth (text only) transport. Finds the Mac helper
/// ("WhisperBridge Bluetooth") by its service UUID, connects, writes framed
/// `BLETextMessage`s and waits for the matching `BLEAck`.
///
/// The message characteristic requires encryption, so the first send triggers
/// the system Bluetooth pairing prompt on both devices; after that the link is
/// encrypted and the bearer token never crosses the air in clear text.
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

    private var readyWaiters: [CheckedContinuation<String?, Never>] = []
    private var writeWaiter: CheckedContinuation<Error?, Never>?
    private var ackWaiters: [UInt16: CheckedContinuation<BLEAck?, Never>] = [:]
    private var busy = false
    private var readyGeneration = 0
    /// How far the current attempt got, for an honest timeout message.
    private enum Stage { case scanning, connecting, discovering, pairing }
    private var stage: Stage = .scanning

    private let serviceUUID = CBUUID(string: BLEProtocol.serviceUUID)
    private let messageUUID = CBUUID(string: BLEProtocol.messageCharacteristicUUID)
    private let ackUUID = CBUUID(string: BLEProtocol.ackCharacteristicUUID)

    public override init() { super.init() }

    // MARK: - Public API

    public func send(text: String, mode: String, enterAfter: Bool, token: String) async -> BridgeClient.Result {
        await perform(BLETextMessage(kind: "send", text: text, mode: mode, enterAfter: enterAfter, token: token),
                      success: { ack in ack.message.isEmpty ? "Sent over Bluetooth" : ack.message })
    }

    /// Like the Wi-Fi Test button: checks the Mac helper and the token without typing.
    public func probe(token: String) async -> BridgeClient.Result {
        await perform(BLETextMessage(kind: "probe", text: "", mode: "type", token: token),
                      success: { _ in "Connected over Bluetooth" })
    }

    /// Starts looking for the Mac helper so the mode pill shows a live state
    /// before the first send. Silent: failures just leave it "Not connected".
    public func warmUp() {
        guard !busy, !connected, readyWaiters.isEmpty else { return }
        Task { _ = await ensureReady() }
    }

    // MARK: - Flow

    private func perform(_ message: BLETextMessage, success: (BLEAck) -> String) async -> BridgeClient.Result {
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
        guard let payload = try? JSONEncoder().encode(message) else {
            return .init(ok: false, message: "Could not encode message")
        }
        let id = nextID
        nextID &+= 1
        let maxWrite = min(peripheral.maximumWriteValueLength(for: .withResponse), 512)
        let frames: [Data]
        do {
            frames = try BLEFraming.frames(payload: payload, messageID: id, maxWrite: maxWrite)
        } catch {
            return .init(ok: false, message: "Text too long for Bluetooth (max 64 KB)")
        }

        for frame in frames {
            let error: Error? = await withCheckedContinuation { cont in
                writeWaiter = cont
                peripheral.writeValue(frame, for: messageChar, type: .withResponse)
            }
            if let error {
                return .init(ok: false, message: "Bluetooth write failed: \(error.localizedDescription)")
            }
        }

        let ack: BLEAck? = await withCheckedContinuation { cont in
            ackWaiters[id] = cont
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.resolveAck(id, nil)
            }
        }
        guard let ack else { return .init(ok: false, message: "No answer from the Mac helper") }
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
            armTimeout(seconds: 15)
            startIfPossible()
        }
        return result
    }

    /// (Re)starts the attempt's deadline. Pairing gets longer: the user has to
    /// accept the system prompt on both the iPhone and the Mac.
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
        let message: String
        switch stage {
        case .scanning:
            message = "Mac helper not found — open WhisperBridge Bluetooth on the Mac (menu bar) and keep Bluetooth on"
        case .connecting:
            message = "Found the Mac but couldn't connect — move closer and tap Test again"
        case .discovering:
            message = "Connected, but the helper didn't answer — quit and reopen WhisperBridge Bluetooth on the Mac"
        case .pairing:
            message = "Pairing didn't finish — accept the Bluetooth pairing prompt on the Mac and the iPhone, then tap Test"
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
                stage = .discovering
                setStatus("Finding the helper…", connected: false)
                peripheral.discoverServices([serviceUUID])
            } else if let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first {
                // Already linked at the system level (e.g. paired earlier): such
                // peripherals don't show up in scans, so reuse the link.
                connect(known)
            } else {
                setStatus("Searching…", connected: false)
                central.scanForPeripherals(withServices: [serviceUUID])
            }
        case .unauthorized:
            finishReady("Allow Bluetooth for Whisper Bridge in Settings")
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
        setStatus("Connecting…", connected: false)
        central?.connect(p)
    }

    private func finishReady(_ problem: String?) {
        guard !readyWaiters.isEmpty else { return }
        readyGeneration += 1
        let waiters = readyWaiters
        readyWaiters.removeAll()
        if problem != nil {
            central?.stopScan()
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
}

extension BluetoothBridge: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state != .poweredOn { dropLink("Bluetooth unavailable") }
            if !readyWaiters.isEmpty { startIfPossible() }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        MainActor.assumeIsolated {
            central.stopScan()
            peerName = advertisedName ?? peripheral.name
            connect(peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            stage = .discovering
            setStatus("Finding the helper…", connected: false)
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated {
            dropLink("Couldn't connect")
            finishReady("Couldn't connect to the Mac helper")
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated { dropLink("Disconnected") }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
                finishReady("Mac helper service missing")
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
                finishReady("Mac helper characteristics missing")
                return
            }
            // Subscribing to the encrypted ack characteristic triggers pairing if needed.
            stage = .pairing
            setStatus("Pairing — accept the prompt on the Mac and iPhone…", connected: false)
            armTimeout(seconds: 60)
            peripheral.setNotifyValue(true, for: ackChar)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                finishReady("Bluetooth pairing failed: \(error.localizedDescription)")
                return
            }
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
        MainActor.assumeIsolated {
            guard characteristic.uuid == ackUUID, let data = characteristic.value,
                  let ack = try? JSONDecoder().decode(BLEAck.self, from: data) else { return }
            resolveAck(ack.id, ack)
        }
    }
}
