import Foundation
import CoreBluetooth

// LXP1 + a big-endian payload length. Notifications may split anywhere,
// including inside the header. Keep this independent of CoreBluetooth for tests.
struct BluetoothFrame {
    private var bytes = Data()
    mutating func append(_ data: Data) throws -> Data? {
        bytes.append(data)
        guard bytes.count <= 32776 else { throw LuxioError.message("Bluetooth response is too large") }
        guard bytes.count >= 8 else { return nil }
        guard bytes.prefix(4) == Data("LXP1".utf8) else { throw LuxioError.message("Invalid Bluetooth response") }
        let size = bytes.dropFirst(4).prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0, size <= 32768, bytes.count <= size + 8 else { throw LuxioError.message("Invalid Bluetooth response size") }
        guard bytes.count == size + 8 else { return nil }
        let result = Data(bytes.dropFirst(8)); bytes.removeAll(keepingCapacity: true); return result
    }
    static func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 32768 else { throw LuxioError.message("Bluetooth request is too large") }
        var length = UInt32(data.count).bigEndian
        return Data("LXP1".utf8) + Data(bytes: &length, count: 4) + data
    }
}

@MainActor final class BluetoothDiscovery: NSObject, @preconcurrency CBCentralManagerDelegate {
    static let service = CBUUID(string: "e97b1000-3c27-4a20-9df4-7d025bc7e451")
    var found: ((BluetoothConnection) -> Void)?
    var status: ((String?) -> Void)?
    private var central: CBCentralManager?
    private var connections: [UUID: BluetoothConnection] = [:]
    private var scanning = false
    func start() {
        scanning = true
        for connection in connections.values { connection.enabled = true }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if let central, central.state == .poweredOn { central.stopScan(); central.scanForPeripherals(withServices: [Self.service]) }
    }
    func stop() {
        scanning = false; central?.stopScan()
        for connection in connections.values { connection.enabled = false; connection.fail(CancellationError()) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status?(nil)
            if scanning { central.scanForPeripherals(withServices: [Self.service]) }
        case .unauthorized: status?("Allow Bluetooth access in Settings to find nearby Luxio devices.")
        case .poweredOff: status?("Turn on Bluetooth to find nearby Luxio devices.")
        case .unsupported: status?("Bluetooth is unavailable on this device.")
        default: break
        }
        if central.state != .poweredOn {
            for connection in connections.values { connection.fail(LuxioError.message("Bluetooth is unavailable")) }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let connection = connections[peripheral.identifier] ?? BluetoothConnection(peripheral: peripheral, central: central)
        connections[peripheral.identifier] = connection
        found?(connection)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connections[peripheral.identifier]?.disconnected(error ?? LuxioError.message("Could not connect to Luxio over Bluetooth"))
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connections[peripheral.identifier]?.disconnected(error ?? LuxioError.message("Luxio disconnected from Bluetooth"))
    }
}

@MainActor final class BluetoothConnection: NSObject, @preconcurrency CBPeripheralDelegate {
    private static let rxID = CBUUID(string: "e97b1001-3c27-4a20-9df4-7d025bc7e451")
    private static let txID = CBUUID(string: "e97b1002-3c27-4a20-9df4-7d025bc7e451")
    let peripheral: CBPeripheral
    var enabled = true
    private let central: CBCentralManager
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var ready = false
    private struct Pending {
        let id: UUID
        let packet: Data
        let timeout: TimeInterval
        let continuation: CheckedContinuation<Data, Error>
    }
    private var queue: [Pending] = []
    private var active: Pending?
    private var timeoutTask: Task<Void, Never>?
    private var draining = false
    private var offset = 0
    private var response = BluetoothFrame()
    var address: String { "ble://" + peripheral.identifier.uuidString }
    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.peripheral = peripheral; self.central = central
        super.init(); peripheral.delegate = self
    }
    func request(_ data: Data, timeout: TimeInterval) async throws -> Data {
        try Task.checkCancellation()
        let packet = try BluetoothFrame.encode(data), id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard enabled, central.state == .poweredOn else { continuation.resume(throwing: LuxioError.message("Turn on Bluetooth to connect to Luxio")); return }
                guard queue.count < 64 else { continuation.resume(throwing: LuxioError.message("Luxio is busy. Try again.")); return }
                queue.append(Pending(id: id, packet: packet, timeout: max(15, timeout), continuation: continuation))
                advance()
            }
        } onCancel: {
            Task { @MainActor in
                if self.active?.id == id { self.fail(CancellationError()) }
                else if let index = self.queue.firstIndex(where: { $0.id == id }) { self.queue.remove(at: index).continuation.resume(throwing: CancellationError()) }
            }
        }
    }
    private func advance() {
        guard !draining, active == nil, !queue.isEmpty, peripheral.state != .disconnecting else { return }
        active = queue.removeFirst(); offset = 0; response = BluetoothFrame()
        let id = active!.id, seconds = active!.timeout
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.active?.id == id else { return }
            self.fail(LuxioError.message("Luxio did not respond over Bluetooth. Move closer and try again."))
        }
        if ready && peripheral.state == .connected { writeChunk() }
        else if peripheral.state == .disconnected { central.connect(peripheral) }
        else if peripheral.state == .connected { peripheral.discoverServices([BluetoothDiscovery.service]) }
    }
    private func writeChunk() {
        guard let active, let rx, offset < active.packet.count else { return }
        let end = min(offset + min(512, peripheral.maximumWriteValueLength(for: .withResponse)), active.packet.count)
        let bytes = active.packet.subdata(in: offset..<end); offset = end
        peripheral.writeValue(bytes, for: rx, type: .withResponse)
    }
    func fail(_ error: Error) {
        timeoutTask?.cancel(); timeoutTask = nil
        ready = false; rx = nil; tx = nil
        let pending = queue; queue.removeAll()
        let current = active; active = nil
        if peripheral.state == .connected || peripheral.state == .connecting { central.cancelPeripheralConnection(peripheral) }
        current?.continuation.resume(throwing: error)
        for item in pending { item.continuation.resume(throwing: error) }
    }
    func disconnected(_ error: Error) {
        // Requests arriving while cancellation was in progress can now reconnect.
        if active != nil { fail(error) }
        ready = false; rx = nil; tx = nil
        advance()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail(error); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == BluetoothDiscovery.service }) else { fail(LuxioError.message("Luxio Bluetooth service is missing")); return }
        peripheral.discoverCharacteristics([Self.rxID, Self.txID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { fail(error); return }
        rx = service.characteristics?.first { $0.uuid == Self.rxID }
        tx = service.characteristics?.first { $0.uuid == Self.txID }
        guard let rx, rx.properties.contains(.write), let tx, tx.properties.contains(.notify) else { fail(LuxioError.message("Luxio Bluetooth characteristics are missing")); return }
        peripheral.setNotifyValue(true, for: tx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail(error); return }
        guard characteristic.uuid == Self.txID, characteristic.isNotifying else { fail(LuxioError.message("Luxio Bluetooth notifications are unavailable")); return }
        ready = true; writeChunk()
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail(error); return }
        writeChunk()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail(error); return }
        guard characteristic.uuid == Self.txID, let bytes = characteristic.value, let active else { return }
        do {
            guard let data = try response.append(bytes) else { return }
            let sent = try Proto.decode(Data(active.packet.dropFirst(8)))
            let received = try Proto.decode(data)
            guard sent.number(1) == received.number(1) else { throw LuxioError.message("Mismatched Bluetooth response") }
            timeoutTask?.cancel(); timeoutTask = nil; self.active = nil; draining = true
            active.continuation.resume(returning: data)
            // The peripheral finishes its notification loop before accepting
            // another frame. Also let the final write acknowledgement drain.
            Task { try? await Task.sleep(for: .milliseconds(30)); self.draining = false; self.advance() }
        } catch { fail(error) }
    }
}
