//
//  FieldwatchViewModel.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import CoreLocation
import CoreBluetooth
import Combine

@MainActor
public final class FieldwatchViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, BleScannerDelegate, WifiScannerDelegate {
    
    // MARK: - Published State
    @Published public var sightings: [String: Sighting] = [:]
    @Published public var isBleScanning: Bool = false
    @Published public var isWifiScanning: Bool = false
    @Published public var scanIntensity: ScanIntensity = .performance
    @Published public var viewMode: ViewMode = .radar
    @Published public var searchQuery: String = ""
    @Published public var selectedRadioFilter: RadioKind? = nil
    @Published public var minRssiThreshold: Int = -100
    @Published public var filterOnlyCoTraveling: Bool = false
    @Published public var filterOnlyIdentified: Bool = false
    
    // Hunting target
    @Published public var huntTargetId: String? = nil
    
    // Location & Stats
    @Published public var currentLocation: CLLocationCoordinate2D?
    @Published public var totalObservationsCount: Int = 0
    @Published public var coTravelingCount: Int = 0
    @Published public var wifiScanMode: WifiScanner.ScanMode = .publicConnectedOnly
    
    // Alerting
    @Published public var coTravelAlert: Sighting? = nil
    
    private let locationManager = CLLocationManager()
    private var lastTakPublishTimes: [String: Date] = [:]
    
    public override init() {
        super.init()
        setupLocation()
        setupRadios()
    }
    
    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func setupRadios() {
        BleScanner.shared.delegate = self
        WifiScanner.shared.delegate = self
        self.wifiScanMode = WifiScanner.shared.activeMode
    }
    
    public func startAllScans() {
        BleScanner.shared.startScanning(intensity: scanIntensity)
        WifiScanner.shared.startScanning()
    }
    
    public func stopAllScans() {
        BleScanner.shared.stopScanning()
        WifiScanner.shared.stopScanning()
    }
    
    public func clearAllSightings() {
        sightings.removeAll()
        totalObservationsCount = 0
        coTravelingCount = 0
        lastTakPublishTimes.removeAll()
    }
    
    // MARK: - Ingestion Pipeline
    public func ingestObservation(_ observation: Observation) {
        totalObservationsCount += 1
        let id = observation.identifier
        
        var sighting = sightings[id] ?? Sighting(
            identifier: id,
            kind: observation.kind,
            name: observation.name,
            firstSeen: observation.timestamp,
            lastSeen: observation.timestamp,
            count: 0,
            lastRssi: observation.rssi,
            maxRssi: observation.rssi,
            location: observation.location,
            facts: observation.facts
        )
        
        // Update basic sighting attributes
        sighting.lastSeen = observation.timestamp
        sighting.count += 1
        sighting.lastRssi = observation.rssi
        if observation.rssi > sighting.maxRssi {
            sighting.maxRssi = observation.rssi
        }
        if observation.name != nil && (sighting.name == nil || sighting.name!.isEmpty) {
            sighting.name = observation.name
        }
        
        // RSSI sparkline history (keep last 20)
        sighting.rssiHistory.append(observation.rssi)
        if sighting.rssiHistory.count > 20 {
            sighting.rssiHistory.removeFirst()
        }
        
        // Update facts
        if !observation.facts.mfgRecords.isEmpty {
            sighting.facts.mfgRecords = observation.facts.mfgRecords
        }
        if !observation.facts.serviceDataRecords.isEmpty {
            sighting.facts.serviceDataRecords = observation.facts.serviceDataRecords
        }
        if !observation.facts.serviceUuids.isEmpty {
            sighting.facts.serviceUuids = observation.facts.serviceUuids
        }
        if observation.facts.vendorOui != nil {
            sighting.facts.vendorOui = observation.facts.vendorOui
        }
        
        // Location history for Co-Travel tracking
        if let loc = observation.location {
            sighting.location = loc
            sighting.locationHistory.append(loc)
            if sighting.locationHistory.count > 30 {
                sighting.locationHistory.removeFirst()
            }
        }
        
        // Match against signatures & catalog
        if let match = SignatureEngine.shared.match(
            name: sighting.name,
            macOrId: sighting.identifier,
            kind: sighting.kind,
            facts: sighting.facts
        ) {
            sighting.fleetId = match.fleetId
            sighting.fleetName = match.fleetName
            sighting.fleetColorIndex = match.colorIndex
        }
        
        // Decoded fields & role hints
        sighting.roleHints = AdvPayloadDecoder.roleHints(for: sighting)
        var decoded: [DecodedField] = []
        for mfg in sighting.facts.mfgRecords {
            decoded.append(contentsOf: AdvPayloadDecoder.decodeManufacturer(record: mfg))
        }
        for sdata in sighting.facts.serviceDataRecords {
            decoded.append(contentsOf: AdvPayloadDecoder.decodeService(record: sdata))
        }
        sighting.decodedFields = decoded
        
        // Evaluate Co-travel ("Moving with you" / Tail detection)
        let wasCoTraveling = sighting.isCoTraveling
        sighting.isCoTraveling = CoTravelEngine.shared.evaluateCoTraveling(
            firstSeen: sighting.firstSeen,
            lastSeen: sighting.lastSeen,
            locationHistory: sighting.locationHistory
        )
        if sighting.isCoTraveling && !wasCoTraveling {
            coTravelingCount += 1
            coTravelAlert = sighting
        }
        
        sightings[id] = sighting
        
        // Throttled TAK Publish (max once every 10 seconds per device)
        let lastPub = lastTakPublishTimes[id] ?? .distantPast
        if observation.timestamp.timeIntervalSince(lastPub) > 10.0 {
            lastTakPublishTimes[id] = observation.timestamp
            TakPublisher.shared.publish(sighting: sighting)
        }
    }
    
    // MARK: - Filtered List for UI
    public var filteredSightings: [Sighting] {
        sightings.values.filter { s in
            if let filterKind = selectedRadioFilter, s.kind != filterKind {
                return false
            }
            if s.lastRssi < minRssiThreshold {
                return false
            }
            if filterOnlyCoTraveling && !s.isCoTraveling {
                return false
            }
            if filterOnlyIdentified && (s.fleetName == nil && s.roleHints.isEmpty) {
                return false
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let nameMatch = s.name?.lowercased().contains(q) ?? false
                let idMatch = s.identifier.lowercased().contains(q)
                let fleetMatch = s.fleetName?.lowercased().contains(q) ?? false
                let hintMatch = s.roleHints.contains(where: { $0.label.lowercased().contains(q) })
                return nameMatch || idMatch || fleetMatch || hintMatch
            }
            return true
        }.sorted { $0.lastRssi > $1.lastRssi }
    }
    
    // MARK: - Delegates
    public nonisolated func bleScannerDidObserve(_ observation: Observation) {
        Task { @MainActor in
            self.ingestObservation(observation)
        }
    }
    
    public nonisolated func bleScannerStateChanged(isScanning: Bool, state: CBManagerState) {
        Task { @MainActor in
            self.isBleScanning = isScanning
        }
    }
    
    public nonisolated func wifiScannerDidObserve(_ observation: Observation) {
        Task { @MainActor in
            self.ingestObservation(observation)
        }
    }
    
    public nonisolated func wifiScannerStateChanged(isScanning: Bool, mode: WifiScanner.ScanMode) {
        Task { @MainActor in
            self.isWifiScanning = isScanning
            self.wifiScanMode = mode
        }
    }
    
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = loc.coordinate
            BleScanner.shared.updateLocation(loc.coordinate)
            WifiScanner.shared.updateLocation(loc.coordinate)
        }
    }
}
