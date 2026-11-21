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

    /// A paired, not-yet-connected AirPods that is nearby, if any. Returns nil while any AirPods are
    /// already connected to this Mac: the user has audio sorted, and the BLE sighting can't tell pairs
    /// apart (the connected pair's own advertisement would otherwise "find" a different paired pair).
    func nearbyCandidate() -> KnownAirPods? {
        guard let last = lastSighting, Date().timeIntervalSince(last) < sightingTTL else { return nil }
        let paired = pairedAirPods()
        guard !paired.contains(where: { $0.device.isConnected() }) else { return nil }
        return paired.first { !$0.device.isConnected() }
    }

    func pairedAirPods() -> [KnownAirPods] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains("AirPods") }
            .map { KnownAirPods(name: $0.name ?? "AirPods", device: $0) }
    }

    /// Battery level of connected AirPods (the lower of the two buds, or the single value for
    /// AirPods Max). Read via IOBluetoothDevice's undocumented battery properties, so this
    /// returns `nil` if they're missing or report 0 (unknown) rather than guessing.
    static func batteryPercent(of device: IOBluetoothDevice) -> Int? {
        func read(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let v = (device.value(forKey: key) as? NSNumber)?.intValue, v > 0 else { return nil }
            return v
        }
        let buds = [read("batteryPercentLeft"), read("batteryPercentRight")].compactMap { $0 }
        return buds.min() ?? read("batteryPercentSingle")
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
        // Byte 7 is the UTP/status byte; bits 1 (0x02) and 3 (0x08) indicate the
        // two buds' in-ear sensors (swapped depending on the flip bit), so any
        // non-zero bit in 0x0A means at least one AirPod is currently in an ear.
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 8, data[0] == 0x4C, data[1] == 0x00, data[2] == 0x07,
              (data[7] & 0x0A) != 0,
              RSSI.intValue != 127, RSSI.intValue >= minRSSI
        else { return }
        lastSighting = Date()
    }
}
