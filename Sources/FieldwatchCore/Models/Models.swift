//
//  Models.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import CoreLocation

extension CLLocationCoordinate2D: @unchecked Sendable {}

public enum RadioKind: String, Codable, CaseIterable, Sendable {
    case wifi = "WIFI"
    case ble = "BLE"
    
    public var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ble: return "Bluetooth LE"
        }
    }
}

public enum ViewMode: String, Codable, CaseIterable, Sendable {
    case radar = "RADAR"
    case list = "LIST"
    case timeline = "TIMELINE"
    case hybrid = "HYBRID"
    case byClass = "BY_CLASS"
    
    public var label: String {
        switch self {
        case .radar: return "Classic radar"
        case .list: return "Strength list"
        case .timeline: return "Timeline"
        case .hybrid: return "Hybrid + sparklines"
        case .byClass: return "By class"
        }
    }
}

public enum ScanIntensity: String, Codable, CaseIterable, Sendable {
    case saver = "SAVER"
    case balanced = "BALANCED"
    case performance = "PERFORMANCE"
    
    public var label: String {
        switch self {
        case .saver: return "Battery Saver"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}

public enum SignatureClass: String, Codable, CaseIterable, Sendable {
    case finder = "FINDER"
    case beacon = "BEACON"
    case signage = "SIGNAGE"
    case wearable = "WEARABLE"
    case surveillance = "SURVEILLANCE"
    case drone = "DRONE"
    case hacking = "HACKING"
    case bodyworn = "BODYWORN"
    case lawEnforcement = "LAW_ENFORCEMENT"
    case vehicle = "VEHICLE"
    case glasses = "GLASSES"
    case audio = "AUDIO"
    case camera = "CAMERA"
    case thermostat = "THERMOSTAT"
    case lock = "LOCK"
    case health = "HEALTH"
    case home = "HOME"
    case isp = "ISP"
    case mesh = "MESH"
    case phone = "PHONE"
    case other = "OTHER"
    
    public var label: String {
        switch self {
        case .finder: return "Finder tags"
        case .beacon: return "Retail beacons"
        case .signage: return "Digital signage"
        case .wearable: return "Wearables"
        case .surveillance: return "Surveillance / ALPR"
        case .drone: return "Drones / RID"
        case .hacking: return "Pen-test / Hacking"
        case .bodyworn: return "Body-worn cameras"
        case .lawEnforcement: return "Law enforcement"
        case .vehicle: return "Vehicles / Telematics"
        case .glasses: return "Smart glasses"
        case .audio: return "Audio / Speakers"
        case .camera: return "Security cameras"
        case .thermostat: return "HVAC / Thermostats"
        case .lock: return "Smart locks"
        case .health: return "Medical / Health"
        case .home: return "Smart home"
        case .isp: return "ISP Gateways"
        case .mesh: return "Mesh nodes"
        case .phone: return "Phones / Tablets"
        case .other: return "Other"
        }
    }
    
    public var icon: String {
        switch self {
        case .finder: return "tag.fill"
        case .beacon: return "antenna.radiowaves.left.and.right"
        case .signage: return "tv.fill"
        case .wearable: return "applewatch"
        case .surveillance: return "video.badge.waveform.fill"
        case .drone: return "airplane"
        case .hacking: return "exclamationmark.shield.fill"
        case .bodyworn: return "person.badge.shield.checkmark.fill"
        case .lawEnforcement: return "shield.fill"
        case .vehicle: return "car.fill"
        case .glasses: return "eyeglasses"
        case .audio: return "headphones"
        case .camera: return "video.fill"
        case .thermostat: return "thermometer.medium"
        case .lock: return "lock.fill"
        case .health: return "heart.fill"
        case .home: return "house.fill"
        case .isp: return "wifi.router.fill"
        case .mesh: return "point.3.filled.connected.trianglepath.dotted"
        case .phone: return "iphone"
        case .other: return "wave.3.right"
        }
    }
}

public struct MfgRecord: Codable, Hashable, Sendable {
    public let companyId: Int
    public let dataHex: String
    
    public init(companyId: Int, dataHex: String) {
        self.companyId = companyId
        self.dataHex = dataHex
    }
}

public struct ServiceDataRecord: Codable, Hashable, Sendable {
    public let uuid: String
    public let dataHex: String
    
    public init(uuid: String, dataHex: String) {
        self.uuid = uuid
        self.dataHex = dataHex
    }
}

public struct RadioFacts: Codable, Sendable {
    public var mfgRecords: [MfgRecord]
    public var serviceDataRecords: [ServiceDataRecord]
    public var serviceUuids: [String]
    public var flags: Int?
    public var txPower: Int?
    public var vendorOui: String?
    public var openDroneIdPayload: String?
    
    public init(
        mfgRecords: [MfgRecord] = [],
        serviceDataRecords: [ServiceDataRecord] = [],
        serviceUuids: [String] = [],
        flags: Int? = nil,
        txPower: Int? = nil,
        vendorOui: String? = nil,
        openDroneIdPayload: String? = nil
    ) {
        self.mfgRecords = mfgRecords
        self.serviceDataRecords = serviceDataRecords
        self.serviceUuids = serviceUuids
        self.flags = flags
        self.txPower = txPower
        self.vendorOui = vendorOui
        self.openDroneIdPayload = openDroneIdPayload
    }
}

public struct RoleHint: Codable, Hashable, Sendable {
    public let bucket: String
    public let label: String
    public let reason: String
    public let weight: Int
    
    public init(bucket: String, label: String, reason: String, weight: Int) {
        self.bucket = bucket
        self.label = label
        self.reason = reason
        self.weight = weight
    }
}

public struct DecodedField: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(label):\(value)" }
    public let label: String
    public let value: String
    
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct Observation: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let kind: RadioKind
    public let identifier: String // MAC address or CoreBluetooth UUID
    public let name: String?
    public let rssi: Int
    public let txPower: Int?
    public let location: CLLocationCoordinate2D?
    public let facts: RadioFacts
    
    public init(
        timestamp: Date = Date(),
        kind: RadioKind,
        identifier: String,
        name: String? = nil,
        rssi: Int,
        txPower: Int? = nil,
        location: CLLocationCoordinate2D? = nil,
        facts: RadioFacts = RadioFacts()
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.identifier = identifier
        self.name = name
        self.rssi = rssi
        self.txPower = txPower
        self.location = location
        self.facts = facts
    }
}

public struct Sighting: Identifiable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let kind: RadioKind
    public var name: String?
    public var vendor: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var count: Int
    public var lastRssi: Int
    public var maxRssi: Int
    public var rssiHistory: [Int] // last 20 samples
    public var location: CLLocationCoordinate2D?
    public var locationHistory: [CLLocationCoordinate2D]
    public var facts: RadioFacts
    public var fleetId: String?
    public var fleetName: String?
    public var fleetColorIndex: Int?
    public var signatureClass: SignatureClass?
    public var roleHints: [RoleHint]
    public var decodedFields: [DecodedField]
    public var isCoTraveling: Bool // "Moving with you"
    public var isBookmarked: Bool
    
    public init(
        identifier: String,
        kind: RadioKind,
        name: String? = nil,
        vendor: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        count: Int = 1,
        lastRssi: Int,
        maxRssi: Int,
        rssiHistory: [Int] = [],
        location: CLLocationCoordinate2D? = nil,
        locationHistory: [CLLocationCoordinate2D] = [],
        facts: RadioFacts = RadioFacts(),
        fleetId: String? = nil,
        fleetName: String? = nil,
        fleetColorIndex: Int? = nil,
        signatureClass: SignatureClass? = nil,
        roleHints: [RoleHint] = [],
        decodedFields: [DecodedField] = [],
        isCoTraveling: Bool = false,
        isBookmarked: Bool = false
    ) {
        self.identifier = identifier
        self.kind = kind
        self.name = name
        self.vendor = vendor
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
        self.lastRssi = lastRssi
        self.maxRssi = maxRssi
        self.rssiHistory = rssiHistory
        self.location = location
        self.locationHistory = locationHistory
        self.facts = facts
        self.fleetId = fleetId
        self.fleetName = fleetName
        self.fleetColorIndex = fleetColorIndex
        self.signatureClass = signatureClass
        self.roleHints = roleHints
        self.decodedFields = decodedFields
        self.isCoTraveling = isCoTraveling
        self.isBookmarked = isBookmarked
    }
}

// Fleet and Signature Rule formats matching dist/fieldwatch-signatures-v2.json
public struct FleetCatalog: Codable, Sendable {
    public let format: String
    public let formatVersion: Int
    public let exportedAt: String?
    public let appVersion: String?
    public let catalogVersion: Int
    public let fleets: [Fleet]
}

public struct Fleet: Codable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var enabled: Bool
    public var matchAny: Bool
    public var colorIndex: Int
    public var rules: [Rule]
}

public struct Rule: Codable, Sendable {
    public let kind: String // "NAME_GLOB", "OUI", "MFG", "SERVICE_DATA", "UUID"
    public let text: String?
    public let companyId: Int?
    public let dataPrefixHex: String?
    public let radio: String? // "WIFI", "BLE", "ANY"
    public let enabled: Bool
}

// MARK: - Display helpers (never show bare "Unknown Device")
public extension Sighting {
    /// Best human-readable title: advertised name > fleet > role hint > vendor > kind fallback.
    var displayName: String {
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        if let f = fleetName, !f.isEmpty { return f }
        if let hint = roleHints.first?.label, !hint.isEmpty { return hint }
        if let v = vendor, !v.isEmpty { return v }
        if kind == .wifi { return "Wi-Fi AP \(String(identifier.prefix(8)))" }
        return "BLE \(String(identifier.prefix(8)))"
    }

    /// Secondary line: vendor / fleet / service info.
    var subtitle: String {
        var parts: [String] = []
        if let v = vendor, !v.isEmpty { parts.append(v) }
        if let f = fleetName, f != displayName { parts.append(f) }
        if let hint = roleHints.first?.label, hint != displayName { parts.append(hint) }
        parts.append(kind == .wifi ? "Wi-Fi" : "BLE")
        return parts.joined(separator: " · ")
    }
}
