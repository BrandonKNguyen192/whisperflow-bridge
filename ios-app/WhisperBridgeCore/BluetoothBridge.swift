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
            readyGeneration += 1
            let generation = readyGeneration
            startIfPossible()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.readyGeneration == generation else { return }
                self.finishReady("Mac helper not found — open WhisperBridge Bluetooth on the Mac and keep Bluetooth on")
            }
        }
        return result
    }

    private func startIfPossible() {
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            if let peripheral, peripheral.state == .connected {
                peripheral.discoverServices([serviceUUID])
            } else if let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first {
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
        peripheral = p
        p.delegate = self
        setStatus("Connecting…", connected: false)
        central?.connect(p)
    }

    private func finishReady(_ problem: String?) {
        guard !readyWaiters.isEmpty else { return }
        readyGeneration += 1
        if problem != nil { central?.stopScan() }
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(returning: problem) }
    }

    private func resolveAck(_ id: UInt16, _ ack: BLEAck?) {
        ackWaiters.removeValue(forKey: id)?.resume(returning: ack)
    }

    private func setStatus(_ text: String, connected: Bool) {
        status = text
        self.connected = connected
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
        MainActor.assumeIsolated {
            central.stopScan()
            connect(peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
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
            setStatus("Connected to \(peripheral.name ?? "Mac")", connected: true)
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
