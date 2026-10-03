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
    @Published public var filterOnlyBookmarked: Bool = false
    @Published public var hideFastPairAccountKey: Bool = false
    
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
    private var lastCoTravelAlertAt: [String: Date] = [:]
    private var lastTrailAppend: Date = .distantPast
    
    public override init() {
        super.init()
        checkReboot()
        setupLocation()
        setupRadios()
    }

    private func checkReboot() {
        let saved = UserDefaults.standard.double(forKey: "fw_last_uptime")
        let now = ProcessInfo.processInfo.systemUptime
        if saved > 0 && saved > now {
            let count = UserDefaults.standard.integer(forKey: "fw_reboot_count") + 1
            UserDefaults.standard.set(count, forKey: "fw_reboot_count")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "fw_last_reboot")
        }
        UserDefaults.standard.set(now, forKey: "fw_last_uptime")
        rebootCount = UserDefaults.standard.integer(forKey: "fw_reboot_count")
    }

    public var lastRebootDate: Date? {
        let t = UserDefaults.standard.double(forKey: "fw_last_reboot")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    
    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.requestAlwaysAuthorization()
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

    // MARK: - Sit sessions (Reports)
    @Published public var activeSit: SitSession?
    @Published public var rebootCount: Int = 0

    public func startSit(name: String) {
        if activeSit != nil { endSit() }
        activeSit = SitSession(name: name, startedAt: Date())
    }

    public func endSit() {
        guard var sit = activeSit else { return }
        let ranked = sightings.values.sorted { $0.lastRssi > $1.lastRssi }
        sit.endedAt = Date()
        sit.deviceCount = ranked.count
        sit.topDevices = ranked.prefix(10).map { "\($0.displayName) (\($0.lastRssi))" }
        SitStore.shared.save(sit)
        activeSit = nil
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
        
        // RSSI sparkline history (keep last 20) + hunt samples (keep last 40)
        sighting.rssiHistory.append(observation.rssi)
        if sighting.rssiHistory.count > 20 {
            sighting.rssiHistory.removeFirst()
        }
        sighting.rssiSamples.append(RssiSample(rssi: observation.rssi, at: observation.timestamp))
        if sighting.rssiSamples.count > 40 {
            sighting.rssiSamples.removeFirst(sighting.rssiSamples.count - 40)
        }

        if let ch = observation.channel {
            sighting.channel = ch
        }

        // Custom bookmark overlay (advertised name stays intact for matching)
        let isFirstSighting = (sighting.count == 1)
        if let custom = Persistence.shared.custom(id: id) {
            sighting.isBookmarked = custom.bookmarked
            if isFirstSighting && custom.alertEnabled {
                Alerter.watched(sighting)
            }
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
        if let connectable = observation.facts.isConnectable {
            sighting.facts.isConnectable = connectable
        }
        
        // Location history for Co-Travel tracking + sit trail (15 s cadence)
        if let loc = observation.location {
            sighting.location = loc
            sighting.locationHistory.append(loc)
            if sighting.locationHistory.count > 30 {
                sighting.locationHistory.removeFirst()
            }
            if activeSit != nil,
               observation.timestamp.timeIntervalSince(lastTrailAppend) > 15 {
                lastTrailAppend = observation.timestamp
                if var sit = activeSit {
                    sit.path.append(TrailPoint(lat: loc.latitude, lon: loc.longitude))
                    if sit.path.count > 2000 {
                        sit.path.removeFirst(sit.path.count - 2000)
                    }
                    activeSit = sit
                }
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

        // Resolve vendor name (Wi-Fi OUI, BLE Company ID)
        if sighting.vendor == nil || sighting.vendor!.isEmpty {
            if observation.kind == .wifi, let oui = observation.facts.vendorOui, !oui.isEmpty,
               let v = VendorLookup.ouiVendor(for: oui) {
                sighting.vendor = v
            } else if let mfg = observation.facts.mfgRecords.first,
                      let v = VendorLookup.companyName(for: mfg.companyId) {
                sighting.vendor = v
            }
        }
        
        // Decoded fields & role hints
        sighting.roleHints = AdvPayloadDecoder.roleHints(for: sighting)
        sighting.fastPairPairing = FastPair.pairingAdvertised(serviceData: sighting.facts.serviceDataRecords)
        var decoded: [DecodedField] = []
        for mfg in sighting.facts.mfgRecords {
            decoded.append(contentsOf: AdvPayloadDecoder.decodeManufacturer(record: mfg))
        }
        for sdata in sighting.facts.serviceDataRecords {
            decoded.append(contentsOf: AdvPayloadDecoder.decodeService(record: sdata))
        }
        sighting.decodedFields = decoded
        
        // Evaluate Co-travel (BLE tags only; Wi-Fi APs never count)
        let wasCoTraveling = sighting.isCoTraveling
        sighting.isCoTraveling = CoTravelEngine.shared.evaluateTag(sighting)
        if sighting.isCoTraveling && !wasCoTraveling {
            coTravelingCount += 1
            coTravelAlert = sighting
            let lastAlert = lastCoTravelAlertAt[id] ?? .distantPast
            if observation.timestamp.timeIntervalSince(lastAlert) > 24 * 3600 {
                lastCoTravelAlertAt[id] = observation.timestamp
                Alerter.coTravel(sighting)
            }
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
            if filterOnlyBookmarked && !s.isBookmarked {
                return false
            }
            if filterOnlyIdentified && (s.fleetName == nil && s.roleHints.isEmpty && s.vendor == nil) {
                return false
            }
            if hideFastPairAccountKey && s.fleetId == FastPair.fleetId && !s.fastPairPairing {
                return false
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let nameMatch = s.name?.lowercased().contains(q) ?? false
                let displayMatch = s.displayName.lowercased().contains(q)
                let idMatch = s.identifier.lowercased().contains(q)
                let fleetMatch = s.fleetName?.lowercased().contains(q) ?? false
                let vendorMatch = s.vendor?.lowercased().contains(q) ?? false
                let hintMatch = s.roleHints.contains(where: { $0.label.lowercased().contains(q) })
                return nameMatch || displayMatch || idMatch || fleetMatch || vendorMatch || hintMatch
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
