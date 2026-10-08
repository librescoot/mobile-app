import CoreBluetooth
import Foundation

struct WatchCandidate: Identifiable {
    let id: UUID
    let name: String
}

/// One central per bounded session; no background scanning or automatic commands.
final class WatchBluetooth: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var targetID: UUID?
    private var name = "Scooter"
    private var action = CompanionAction.refresh
    private var completion: ((String) -> Void)?
    private var publish: ((CompanionSnapshot) -> Void)?
    private var scanCompletion: (([WatchCandidate]) -> Void)?
    private var candidates: [UUID: WatchCandidate] = [:]
    private var timer: Timer?
    private var started = false
    private var issued = false
    private var deadline: TimeInterval = 0
    private var pendingServices = Set<CBUUID>()
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var reads: [CBUUID] = []
    private var expected: CBUUID?
    private var values: [CBUUID: Data] = [:]
    private var confirming = false
    private var readingBatteries = false

    private static func uuid(_ short: String) -> CBUUID {
        CBUUID(string: "9a59\(short)-6e67-5d0d-aab9-ad9126b66f91")
    }
    private let control = WatchBluetooth.uuid("0000"), stateService = WatchBluetooth.uuid("0020"), batteryService = WatchBluetooth.uuid("00e0")
    private let command = WatchBluetooth.uuid("0001"), state = WatchBluetooth.uuid("0021"), seat = WatchBluetooth.uuid("0022")

    func scan(completion: @escaping ([WatchCandidate]) -> Void) {
        scanCompletion = completion
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.finishScan() }
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func execute(id: UUID, name: String, action: CompanionAction, pairing: Bool,
                 publish: @escaping (CompanionSnapshot) -> Void, completion: @escaping (String) -> Void) {
        guard !pairing || action == .refresh else { completion("invalid"); return }
        targetID = id
        self.name = name
        self.action = action
        self.publish = publish
        self.completion = completion
        deadline = ProcessInfo.processInfo.systemUptime + (pairing ? 60 : 15)
        timer = Timer.scheduledTimer(withTimeInterval: pairing ? 60 : 15, repeats: false) { [weak self] _ in self?.fail() }
        central = CBCentralManager(delegate: self, queue: .main)
    }
    private func finishScan() {
        let callback = scanCompletion
        scanCompletion = nil
        cleanup()
        callback?(candidates.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }
    private func finish(_ result: String) {
        let callback = completion
        completion = nil
        cleanup()
        callback?(result)
    }
    private func fail() {
        if scanCompletion != nil { finishScan() }
        else { finish(issued ? "unknown" : "unavailable") }
    }
    func cancel() { fail() }
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        central?.stopScan()
        if let target { central?.cancelPeripheralConnection(target); target.delegate = nil }
        central?.delegate = nil
        central = nil
        target = nil
        expected = nil
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if [.poweredOff, .unauthorized, .unsupported].contains(central.state) { fail() }
            return
        }
        guard !started else { return }
        started = true
        if let id = targetID, let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(peripheral)
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let targetID {
            if peripheral.identifier == targetID { central.stopScan(); connect(peripheral) }
            return
        }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard advertisedName == "unu Scooter" || manufacturer?.starts(with: [0x0a, 0xe5]) == true || services.contains(control) else { return }
        candidates[peripheral.identifier] = WatchCandidate(id: peripheral.identifier, name: advertisedName ?? "Scooter")
    }
    private func connect(_ peripheral: CBPeripheral) {
        guard completion != nil, target == nil else { return }
        target = peripheral
        peripheral.delegate = self
        central?.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === target, completion != nil else { return }
        peripheral.discoverServices([control, stateService, batteryService])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral === target { fail() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral === target { fail() }
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        if peripheral === target { fail() }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === target, completion != nil else { return }
        guard error == nil, let services = peripheral.services,
              services.contains(where: { $0.uuid == control }), services.contains(where: { $0.uuid == stateService }) else { fail(); return }
        pendingServices = Set(services.map(\.uuid))
        for service in services {
            let wanted: [CBUUID]
            switch service.uuid {
            case control: wanted = [command]
            case stateService: wanted = [state, seat]
            case batteryService: wanted = [Self.uuid("00e3"), Self.uuid("00e9"), Self.uuid("00ef"), Self.uuid("00f5")]
            default: pendingServices.remove(service.uuid); continue
            }
            peripheral.discoverCharacteristics(wanted, for: service)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === target, completion != nil, pendingServices.contains(service.uuid) else { return }
        guard error == nil else { fail(); return }
        for characteristic in service.characteristics ?? [] { chars[characteristic.uuid] = characteristic }
        pendingServices.remove(service.uuid)
        guard pendingServices.isEmpty else { return }
        guard chars[command]?.properties.contains(.write) == true,
              chars[state]?.properties.contains(.read) == true, chars[seat]?.properties.contains(.read) == true else { fail(); return }
        readState()
    }
    private func readState() {
        guard completion != nil else { return }
        values = [:]
        reads = [state, seat]
        readNext()
    }
    private func readNext() {
        guard completion != nil else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { fail(); return }
        guard !reads.isEmpty else { observed(); return }
        let id = reads.removeFirst()
        guard let characteristic = chars[id] else { fail(); return }
        expected = id
        target?.readValue(for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === target, completion != nil, expected == characteristic.uuid else { return }
        guard error == nil, let data = characteristic.value else { fail(); return }
        expected = nil
        values[characteristic.uuid] = data
        readNext()
    }
    private func observed() {
        guard completion != nil else { return }
        if readingBatteries { confirmed(); return }
        let vehicle = values[state].map(CompanionSnapshot.text)
        let seatClosed: Bool? = values[seat].map(CompanionSnapshot.text).flatMap { $0 == "closed" ? true : ($0 == "open" ? false : nil) }
        if !confirming && !action.allows(vehicle) { finish("unsafeState"); return }
        if action.confirms(vehicle, seatClosed: seatClosed) {
            if action == .refresh {
                readingBatteries = true
                reads = ["00e3", "00e9", "00ef", "00f5"].map(Self.uuid).filter { chars[$0]?.properties.contains(.read) == true }
                readNext()
            } else { confirmed() }
        } else if !confirming {
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let characteristic = chars[command], let wire = action.wire else { fail(); return }
            // Exactly one write; neither timeout nor disconnection schedules a retry.
            issued = true
            confirming = true
            target?.writeValue(Data(wire.utf8), for: characteristic, type: .withResponse)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.readState() }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === target, completion != nil, characteristic.uuid == command else { return }
        guard error == nil else { fail(); return }
        readState()
    }
    private func confirmed() {
        guard let targetID else { fail(); return }
        var snapshot = CompanionSnapshot(scooterId: targetID.uuidString, name: name)
        snapshot.state = values[state].map(CompanionSnapshot.text)
        snapshot.seatClosed = values[seat].map(CompanionSnapshot.text).flatMap { $0 == "closed" ? true : ($0 == "open" ? false : nil) }
        snapshot.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        func charge(_ present: String, _ soc: String) -> Int? {
            guard values[Self.uuid(present)].flatMap(CompanionSnapshot.uint32) == 1,
                  let value = values[Self.uuid(soc)].flatMap(CompanionSnapshot.uint32), value <= 100 else { return nil }
            return Int(value)
        }
        snapshot.battery1 = charge("00e3", "00e9")
        snapshot.battery2 = charge("00ef", "00f5")
        snapshot.rangeKm = CompanionSnapshot.range(snapshot.battery1, snapshot.battery2)
        publish?(snapshot)
        finish("confirmed")
    }
}
