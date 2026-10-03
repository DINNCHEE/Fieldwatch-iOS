//
//  WifiScanner.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import NetworkExtension
import CoreLocation
#if canImport(Darwin)
import Darwin
#endif

public protocol WifiScannerDelegate: AnyObject, Sendable {
    func wifiScannerDidObserve(_ observation: Observation)
    func wifiScannerStateChanged(isScanning: Bool, mode: WifiScanner.ScanMode)
}

public final class WifiScanner: NSObject, @unchecked Sendable {
    public static let shared = WifiScanner()
    
    public enum ScanMode: String, Sendable {
        case publicConnectedOnly = "App Store (Connected AP Only)"
        case privateMobileWiFi = "Native Sniffer (MobileWiFi Private API)"
        case companionHardware = "Companion Sniffer (ESP32 / UDP Bridge)"
    }
    
    public weak var delegate: WifiScannerDelegate?
    private(set) public var isScanning = false
    private(set) public var activeMode: ScanMode = .publicConnectedOnly
    
    private var scanTimer: Timer?
    private let queue = DispatchQueue(label: "app.fieldwatch.wifi.scanner", qos: .userInitiated)
    private var currentLocation: CLLocationCoordinate2D?
    
    // Private MobileWiFi symbols if dynamically loaded
    private var mobileWiFiHandle: UnsafeMutableRawPointer?
    
    public override init() {
        super.init()
        detectAvailableMode()
    }
    
    private func detectAvailableMode() {
        // Test if MobileWiFi.framework is loadable (TrollStore / Jailbreak / Debug build)
        if let handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY) {
            mobileWiFiHandle = handle
            activeMode = .privateMobileWiFi
            print("WifiScanner: MobileWiFi.framework loaded. Full passive 802.11 scanning enabled!")
        } else {
            activeMode = .publicConnectedOnly
            print("WifiScanner: MobileWiFi not accessible. Operating in standard App Store mode.")
        }
    }
    
    public func updateLocation(_ location: CLLocationCoordinate2D?) {
        queue.async {
            self.currentLocation = location
        }
    }
    
    public func startScanning(interval: TimeInterval = 5.0) {
        queue.async {
            guard !self.isScanning else { return }
            self.isScanning = true
            
            DispatchQueue.main.async {
                self.delegate?.wifiScannerStateChanged(isScanning: true, mode: self.activeMode)
                self.scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    self?.performScanCycle()
                }
                self.performScanCycle()
            }
        }
    }
    
    public func stopScanning() {
        queue.async {
            guard self.isScanning else { return }
            self.isScanning = false
            DispatchQueue.main.async {
                self.scanTimer?.invalidate()
                self.scanTimer = nil
                self.delegate?.wifiScannerStateChanged(isScanning: false, mode: self.activeMode)
            }
        }
    }
    
    private func performScanCycle() {
        queue.async {
            switch self.activeMode {
            case .privateMobileWiFi:
                self.performPrivateMobileWiFiScan()
            case .publicConnectedOnly:
                self.performPublicConnectedScan()
            case .companionHardware:
                break // Managed via external network packets
            }
        }
    }
    
    // MARK: - Public Mode: Connected Network Details
    private func performPublicConnectedScan() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            guard let self = self, let network = network else { return }
            let ssid = network.ssid
            let bssid = network.bssid
            let signal = network.signalStrength // 0.0 to 1.0
            let estimatedRssi = Int(-100 + (signal * 50)) // map ~ -100 to -50 dBm
            
            let facts = RadioFacts(
                vendorOui: self.extractOui(from: bssid)
            )
            
            let observation = Observation(
                timestamp: Date(),
                kind: .wifi,
                identifier: bssid,
                name: ssid,
                rssi: estimatedRssi,
                location: self.currentLocation,
                facts: facts
            )
            
            self.delegate?.wifiScannerDidObserve(observation)
        }
    }
    
    // MARK: - Private MobileWiFi Mode (Sideload / Jailbreak)
    private func performPrivateMobileWiFiScan() {
        guard let handle = mobileWiFiHandle else {
            performPublicConnectedScan()
            return
        }
        
        typealias WiFiManagerClientCreateFunc = @convention(c) (CFAllocator?, Int) -> UnsafeMutableRawPointer?
        typealias WiFiManagerClientCopyDevicesFunc = @convention(c) (UnsafeMutableRawPointer?) -> CFArray?
        
        guard let createSym = dlsym(handle, "WiFiManagerClientCreate"),
              let copyDevicesSym = dlsym(handle, "WiFiManagerClientCopyDevices") else {
            performPublicConnectedScan()
            return
        }
        
        let clientCreate = unsafeBitCast(createSym, to: WiFiManagerClientCreateFunc.self)
        let copyDevices = unsafeBitCast(copyDevicesSym, to: WiFiManagerClientCopyDevicesFunc.self)
        
        guard let manager = clientCreate(kCFAllocatorDefault, 0),
              let devices = copyDevices(manager) as? [AnyObject],
              let device = devices.first else {
            performPublicConnectedScan()
            return
        }
        
        // Scan asynchronously on first device
        typealias WiFiDeviceClientScanAsyncFunc = @convention(c) (
            AnyObject,
            CFDictionary?,
            @convention(block) (AnyObject?, CFArray?, Int) -> Void,
            UnsafeMutableRawPointer?
        ) -> Int
        
        if let scanSym = dlsym(handle, "WiFiDeviceClientScanAsync") {
            let scanAsync = unsafeBitCast(scanSym, to: WiFiDeviceClientScanAsyncFunc.self)
            _ = scanAsync(device, nil, { [weak self] _, networks, error in
                guard let self = self, error == 0, let networkList = networks as? [AnyObject] else { return }
                self.parseMobileWiFiNetworks(networkList)
            }, nil)
        } else {
            performPublicConnectedScan()
        }
    }
    
    private func parseMobileWiFiNetworks(_ networks: [AnyObject]) {
        guard let handle = mobileWiFiHandle else { return }
        typealias WiFiNetworkGetPropertyFunc = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
        guard let getPropSym = dlsym(handle, "WiFiNetworkGetProperty") else { return }
        let getProp = unsafeBitCast(getPropSym, to: WiFiNetworkGetPropertyFunc.self)
        
        for net in networks {
            let ssidRef = getProp(net, "SSID" as CFString)
            let bssidRef = getProp(net, "BSSID" as CFString)
            let rssiRef = getProp(net, "RSSI" as CFString)
            
            let ssid = ssidRef?.takeUnretainedValue() as? String ?? "<Hidden>"
            guard let bssid = bssidRef?.takeUnretainedValue() as? String else { continue }
            let rssi = rssiRef?.takeUnretainedValue() as? Int ?? -80
            
            let facts = RadioFacts(
                vendorOui: extractOui(from: bssid)
            )
            
            let observation = Observation(
                timestamp: Date(),
                kind: .wifi,
                identifier: bssid,
                name: ssid,
                rssi: rssi,
                location: currentLocation,
                facts: facts
            )
            
            delegate?.wifiScannerDidObserve(observation)
        }
    }
    
    // MARK: - Ingestion from External Companion Hardware (ESP32 Marauder / Bridge)
    public func ingestCompanionPacket(
        bssid: String,
        ssid: String?,
        rssi: Int,
        channel: Int?,
        vendorOui: String?
    ) {
        let facts = RadioFacts(vendorOui: vendorOui ?? extractOui(from: bssid))
        let observation = Observation(
            timestamp: Date(),
            kind: .wifi,
            identifier: bssid,
            name: ssid,
            rssi: rssi,
            location: currentLocation,
            facts: facts
        )
        delegate?.wifiScannerDidObserve(observation)
    }
    
    private func extractOui(from mac: String) -> String {
        let parts = mac.split(separator: ":")
        if parts.count >= 3 {
            return "\(parts[0]):\(parts[1]):\(parts[2])".uppercased()
        }
        return ""
    }
}
