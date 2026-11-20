import CoreBluetooth
import IOBluetooth

struct KnownAirPods {
    let name: String
    let device: IOBluetoothDevice
}

/// Finds AirPods that are paired with this Mac, aren't currently connected to it,
/// and are physically nearby (seen via Apple's BLE "proximity pairing" advertisements).
final class AirPodsMonitor: NSObject, CBCentralManagerDelegate {
    /// Only count AirPods as nearby if their advert is at least this strong (dBm).
    private let minRSSI = -75
    /// How long a BLE sighting stays valid.
    private let sightingTTL: TimeInterval = 15

    private var central: CBCentralManager?
    private var lastSighting: Date?

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// A paired, not-yet-connected AirPods that is nearby, if any.
    func nearbyCandidate() -> KnownAirPods? {
        guard let last = lastSighting, Date().timeIntervalSince(last) < sightingTTL else { return nil }
        return pairedAirPods().first { !$0.device.isConnected() }
    }

    func pairedAirPods() -> [KnownAirPods] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains("AirPods") }
            .map { KnownAirPods(name: $0.name ?? "AirPods", device: $0) }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // Apple company ID 0x004C, type 0x07 = AirPods "proximity pairing".
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 3, data[0] == 0x4C, data[1] == 0x00, data[2] == 0x07,
              RSSI.intValue != 127, RSSI.intValue >= minRSSI
        else { return }
        lastSighting = Date()
    }
}
