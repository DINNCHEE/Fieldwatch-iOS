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
    private let queue = DispatchQueue(label: "app.fieldwatch.ble.scanner", qos: .userInitiated)
    private var currentLocation: CLLocationCoordinate2D?
    
    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }
    
    public func updateLocation(_ location: CLLocationCoordinate2D?) {
        queue.async {
            self.currentLocation = location
        }
    }
    
    public func startScanning(intensity: ScanIntensity = .performance) {
        queue.async {
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
            DispatchQueue.main.async {
                self.delegate?.bleScannerStateChanged(isScanning: true, state: self.centralManager.state)
            }
            print("BleScanner: Started BLE scan with intensity: \(intensity.rawValue)")
        }
    }
    
    public func stopScanning() {
        queue.async {
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
            txPower: txPower
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
