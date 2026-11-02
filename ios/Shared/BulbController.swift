import CoreBluetooth
import Foundation

/// Commands understood by Triones / "Happy Lighting" BLE bulbs.
enum LampCommand {
    case on
    case off

    var payload: Data {
        switch self {
        case .on:  return Data([0xCC, 0x23, 0x33])
        case .off: return Data([0xCC, 0x24, 0x33])
        }
    }
}

enum BulbError: LocalizedError {
    case bluetoothOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case noBulbChosen
    case bulbNotFound
    case connectionFailed
    case notATrionesBulb
    case timedOut

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Bluetooth is turned off."
        case .bluetoothUnauthorized:
            return "Lamp doesn't have Bluetooth permission. Turn it on in Settings › Lamp."
        case .bluetoothUnsupported:
            return "Bluetooth LE isn't available on this device."
        case .noBulbChosen:
            return "Open the Lamp app and pick your bulb first."
        case .bulbNotFound:
            return "Couldn't find the saved bulb. Open the Lamp app and pick it again."
        case .connectionFailed:
            return "Couldn't connect to the bulb. Is it powered and in range? Close Happy Lighting if it's open."
        case .notATrionesBulb:
            return "That device doesn't look like a Triones bulb."
        case .timedOut:
            return "The bulb didn't respond in time. Move closer and try again."
        }
    }
}

struct DiscoveredBulb: Identifiable, Equatable {
    let id: UUID
    let name: String
    var rssi: Int

    var looksLikeTriones: Bool {
        let lower = name.lowercased()
        return lower.contains("triones") || lower.contains("ledble") || lower.contains("ledblue")
    }
}

/// Talks to the bulb over Bluetooth LE.
///
/// All Core Bluetooth state lives on a private serial queue. Commands are queued
/// and executed one after another: connect → discover → write → (idle) disconnect.
/// The connection is dropped a few seconds after the last command so that the
/// Happy Lighting app can still connect (the bulb accepts only one connection).
final class BulbController: NSObject {
    static let shared = BulbController()

    // Triones bulbs use FFD5/FFD9. Some near-identical clones use FFE5/FFE9.
    private static let serviceUUIDs = [CBUUID(string: "FFD5"), CBUUID(string: "FFE5")]
    private static let writeUUIDs = [CBUUID(string: "FFD9"), CBUUID(string: "FFE9")]

    private static let savedIDKey = "savedBulbID"
    private static let savedNameKey = "savedBulbName"

    private let queue = DispatchQueue(label: "com.managereduard.lampcontrol.ble")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var connecting = false

    private struct Job {
        let id = UUID()
        let payload: Data
        let completion: (Result<Void, Error>) -> Void
    }
    private var jobs: [Job] = []
    private var jobTimeout: DispatchWorkItem?
    private var idleDisconnect: DispatchWorkItem?

    private var scanHandler: ((DiscoveredBulb) -> Void)?

    private override init() {
        super.init()
        // Created on our queue; every other access is also queued after this.
        queue.async {
            self.central = CBCentralManager(
                delegate: self,
                queue: self.queue,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        }
    }

    // MARK: - Saved bulb

    var savedBulbName: String? {
        UserDefaults.standard.string(forKey: Self.savedNameKey)
    }

    private var savedBulbID: UUID? {
        UserDefaults.standard.string(forKey: Self.savedIDKey).flatMap(UUID.init(uuidString:))
    }

    func saveBulb(_ bulb: DiscoveredBulb) {
        UserDefaults.standard.set(bulb.id.uuidString, forKey: Self.savedIDKey)
        UserDefaults.standard.set(bulb.name, forKey: Self.savedNameKey)
        queue.async { self.dropConnection() }
    }

    // MARK: - Sending commands

    func send(_ command: LampCommand) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.jobs.append(Job(payload: command.payload) { continuation.resume(with: $0) })
                if self.jobs.count == 1 { self.startNextJob() }
            }
        }
    }

    private func startNextJob() {
        guard let job = jobs.first else { return }
        idleDisconnect?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishJob(.failure(BulbError.timedOut), jobID: job.id)
        }
        jobTimeout = timeout
        queue.asyncAfter(deadline: .now() + 10, execute: timeout)
        advance()
    }

    private func finishJob(_ result: Result<Void, Error>, jobID: UUID? = nil) {
        guard let job = jobs.first else { return }
        if let jobID, job.id != jobID { return }
        jobTimeout?.cancel()
        jobTimeout = nil
        jobs.removeFirst()
        job.completion(result)

        if case .failure = result { dropConnection() }
        if jobs.isEmpty {
            scheduleIdleDisconnect()
        } else {
            startNextJob()
        }
    }

    /// Moves the current job one step forward based on the current state.
    private func advance() {
        guard let job = jobs.first, let central else { return }

        switch central.state {
        case .poweredOn:
            break
        case .unknown, .resetting:
            return // wait for centralManagerDidUpdateState
        case .poweredOff:
            finishJob(.failure(BulbError.bluetoothOff)); return
        case .unauthorized:
            finishJob(.failure(BulbError.bluetoothUnauthorized)); return
        default:
            finishJob(.failure(BulbError.bluetoothUnsupported)); return
        }

        if let peripheral, peripheral.state == .connected {
            if let characteristic = writeCharacteristic {
                write(job, to: characteristic, on: peripheral)
            }
            // else: service discovery is in progress; its callback calls advance().
            return
        }

        if connecting { return }

        guard let id = savedBulbID else {
            finishJob(.failure(BulbError.noBulbChosen)); return
        }
        let target = (peripheral?.identifier == id ? peripheral : nil)
            ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let target else {
            finishJob(.failure(BulbError.bulbNotFound)); return
        }

        peripheral = target
        target.delegate = self
        writeCharacteristic = nil
        connecting = true
        central.connect(target, options: nil)
    }

    private func write(_ job: Job, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        if characteristic.properties.contains(.writeWithoutResponse) {
            peripheral.writeValue(job.payload, for: characteristic, type: .withoutResponse)
            // No acknowledgement is coming; give the radio a moment to flush.
            queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.finishJob(.success(()), jobID: job.id)
            }
        } else {
            peripheral.writeValue(job.payload, for: characteristic, type: .withResponse)
            // Finished in peripheral(_:didWriteValueFor:error:)
        }
    }

    private func scheduleIdleDisconnect() {
        idleDisconnect?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.dropConnection() }
        idleDisconnect = item
        queue.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func dropConnection() {
        idleDisconnect?.cancel()
        idleDisconnect = nil
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        writeCharacteristic = nil
        connecting = false
    }

    // MARK: - Scanning (used by the app's setup screen)

    func startScanning(_ handler: @escaping (DiscoveredBulb) -> Void) {
        queue.async {
            self.scanHandler = handler
            self.beginScan()
        }
    }

    func stopScanning() {
        queue.async {
            self.scanHandler = nil
            if self.central?.state == .poweredOn { self.central?.stopScan() }
        }
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn, scanHandler != nil else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BulbController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            beginScan()
        } else {
            peripheral = nil
            writeCharacteristic = nil
            connecting = false
        }
        advance()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        connecting = false
        peripheral.discoverServices(Self.serviceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        connecting = false
        finishJob(.failure(BulbError.connectionFailed))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        connecting = false
        writeCharacteristic = nil
        self.peripheral = nil
        if !jobs.isEmpty { finishJob(.failure(BulbError.connectionFailed)) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let handler = scanHandler else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        guard let name, !name.isEmpty else { return }
        let bulb = DiscoveredBulb(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        DispatchQueue.main.async { handler(bulb) }
    }
}

// MARK: - CBPeripheralDelegate

extension BulbController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { Self.serviceUUIDs.contains($0.uuid) })
        else {
            finishJob(.failure(BulbError.notATrionesBulb)); return
        }
        peripheral.discoverCharacteristics(Self.writeUUIDs, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { Self.writeUUIDs.contains($0.uuid) })
        else {
            finishJob(.failure(BulbError.notATrionesBulb)); return
        }
        writeCharacteristic = characteristic
        advance()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if error != nil {
            finishJob(.failure(BulbError.connectionFailed))
        } else {
            finishJob(.success(()))
        }
    }
}
