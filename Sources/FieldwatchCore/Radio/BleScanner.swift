//
//  BleScanner.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import CoreBluetooth
import CoreLocation

public protocol BleScannerDelegate: AnyObject, Sendable {
    func bleScannerDidObserve(_ observation: Observation)
    func bleScannerStateChanged(isScanning: Bool, state: CBManagerState)
}

public final class BleScanner: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    public static let shared = BleScanner()
    
    private var centralManager: CBCentralManager!
    public weak var delegate: BleScannerDelegate?
    
    private(set) public var isScanning = false
    private var wantsScan = false
    private let queue = DispatchQueue(label: "app.fieldwatch.ble.scanner", qos: .userInitiated)
    private var currentLocation: CLLocationCoordinate2D?

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: "app.fieldwatch.ble"
        ])
    }
    
    public func updateLocation(_ location: CLLocationCoordinate2D?) {
        queue.async {
            self.currentLocation = location
        }
    }
    
    public func startScanning(intensity: ScanIntensity = .performance) {
        queue.async {
            self.wantsScan = true
            guard self.centralManager.state == .poweredOn else {
                print("BleScanner: Bluetooth not powered on (state: \(self.centralManager.state.rawValue))")
                return
            }

            guard !self.isScanning else { return }
            
            // AllowDuplicates is essential for real-time radar sweep and RSSI tracking
            let options: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: (intensity != .saver)
            ]
            
            self.centralManager.scanForPeripherals(withServices: nil, options: options)
            self.isScanning = true
            self.harvestSystemConnected()
            DispatchQueue.main.async {
                self.delegate?.bleScannerStateChanged(isScanning: true, state: self.centralManager.state)
            }
            print("BleScanner: Started BLE scan with intensity: \(intensity.rawValue)")
        }
    }
    
    public func stopScanning() {
        queue.async {
            self.wantsScan = false
            guard self.isScanning else { return }
            self.centralManager.stopScan()
            self.isScanning = false
            DispatchQueue.main.async {
                self.delegate?.bleScannerStateChanged(isScanning: false, state: self.centralManager.state)
            }
            print("BleScanner: Stopped BLE scan")
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.delegate?.bleScannerStateChanged(isScanning: self.isScanning, state: central.state)
        }
        if central.state == .poweredOn && isScanning {
            startScanning()
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Relaunched in background: resume the air watch if the user left it on.
        if wantsScan && central.state == .poweredOn {
            queue.async { [weak self] in
                guard let self = self, !self.isScanning else { return }
                self.centralManager.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
                self.isScanning = true
                self.harvestSystemConnected()
            }
        }
    }

    /// System-paired/connected accessories (AirPods, watches, speakers…).
    /// iOS hides their advertisements from us, but tells us they exist —
    /// with their real names. No connection is opened.
    private func harvestSystemConnected() {
        let serviceStrings = [
            "1800", "1801", "180A", "180D", "180F", "1812", "181A",
            "1802", "1803", "1805", "1826", "181C", "1808", "1811",
            "1822", "183E", "181D", "180E", "1810", "181B",
        ]
        var seen = Set<String>()
        for uuid in serviceStrings.map({ CBUUID(string: $0) }) {
            for peripheral in centralManager.retrieveConnectedPeripherals(withServices: [uuid]) {
                let id = peripheral.identifier.uuidString
                guard seen.insert(id).inserted else { continue }
                let observation = Observation(
                    timestamp: Date(),
                    kind: .ble,
                    identifier: id,
                    name: peripheral.name,
                    rssi: -60,
                    location: currentLocation,
                    facts: RadioFacts(
                        serviceUuids: [uuid.uuidString]
                    )
                )
                delegate?.bleScannerDidObserve(observation)
            }
        }
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let now = Date()
        let identifier = peripheral.identifier.uuidString
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        
        var mfgRecords: [MfgRecord] = []
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfgData.count >= 2 {
            let companyId = Int(mfgData[0]) | (Int(mfgData[1]) << 8)
            let payload = mfgData.count > 2 ? mfgData.subdata(in: 2..<mfgData.count) : Data()
            mfgRecords.append(MfgRecord(companyId: companyId, dataHex: payload.hexUpper))
        }
        
        var serviceDataRecords: [ServiceDataRecord] = []
        if let sdataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (cbuuid, data) in sdataDict {
                serviceDataRecords.append(ServiceDataRecord(uuid: cbuuid.uuidString, dataHex: data.hexUpper))
            }
        }
        
        var serviceUuids: [String] = []
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUuids.append(contentsOf: uuids.map { $0.uuidString })
        }
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            serviceUuids.append(contentsOf: overflow.map { $0.uuidString })
        }
        
        let facts = RadioFacts(
            mfgRecords: mfgRecords,
            serviceDataRecords: serviceDataRecords,
            serviceUuids: serviceUuids,
            txPower: txPower,
            isConnectable: connectable
        )
        
        let observation = Observation(
            timestamp: now,
            kind: .ble,
            identifier: identifier,
            name: localName,
            rssi: RSSI.intValue,
            txPower: txPower,
            location: currentLocation,
            facts: facts
        )
        
        delegate?.bleScannerDidObserve(observation)
    }
}
