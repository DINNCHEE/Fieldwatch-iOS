//
//  AdvPayloadDecoder.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation

public struct AdvPayloadDecoder: Sendable {
    
    // MARK: - Decoded Manufacturer Payload
    public static func decodeManufacturer(record: MfgRecord) -> [DecodedField] {
        guard let data = Data(hexString: record.dataHex) else { return [] }
        switch record.companyId {
        case 0x004C: // Apple Inc.
            return decodeApple(data: data)
        case 0x0006: // Microsoft
            return decodeMicrosoft(data: data)
        case 0x0157: // AltBeacon (Radius Networks)
            return decodeAltBeacon(data: data)
        case 0x0075: // Samsung Electronics
            return decodeSamsung(data: data)
        default:
            return [DecodedField(label: "Manufacturer Payload", value: "\(data.count) bytes")]
        }
    }
    
    // MARK: - Decoded Service Data Payload
    public static func decodeService(record: ServiceDataRecord) -> [DecodedField] {
        guard let data = Data(hexString: record.dataHex) else { return [] }
        let shortUuid = record.uuid.replacingOccurrences(of: "-", with: "").uppercased()
        
        if shortUuid.contains("FE2C") {
            return decodeFastPair(data: data)
        } else if shortUuid.contains("FEAA") {
            return decodeEddystone(data: data)
        } else if shortUuid.contains("FFFA") || shortUuid.contains("FA") {
            return decodeOpenDroneId(data: data)
        }
        return [DecodedField(label: "Service Data", value: "\(data.count) bytes (UUID: \(record.uuid))")]
    }
    
    // MARK: - Role Hints & Device Profiling
    public static func roleHints(for sighting: Sighting) -> [RoleHint] {
        var hints: [RoleHint] = []
        
        // 1. Check Apple TLVs
        for rec in sighting.facts.mfgRecords where rec.companyId == 0x004C {
            guard let data = Data(hexString: rec.dataHex) else { continue }
            let tlvs = parseAppleTLVs(data: data)
            for tlv in tlvs {
                switch tlv.type {
                case 0x02: // iBeacon
                    let hex = tlv.data.hexUpper
                    if hex.contains("74278BDA") {
                        hints.append(RoleHint(bucket: "vehicle", label: "Tesla Phone-Key", reason: "Tesla phone-key iBeacon UUID profile", weight: 9))
                    } else if hex.contains("F0018B9D") {
                        hints.append(RoleHint(bucket: "beacon", label: "Target Atrius Basket Tag", reason: "Target shopping basket asset tracker", weight: 9))
                    } else {
                        hints.append(RoleHint(bucket: "beacon", label: "Apple iBeacon", reason: "iBeacon proximity transmitter", weight: 7))
                    }
                case 0x05:
                    hints.append(RoleHint(bucket: "phone", label: "Apple AirDrop", reason: "Active AirDrop sharing advertisement", weight: 6))
                case 0x07:
                    let model = decodeAirPodsModel(data: tlv.data)
                    hints.append(RoleHint(bucket: "audio-personal", label: model ?? "AirPods / Beats", reason: "Apple Proximity Pairing broadcast", weight: 8))
                case 0x08:
                    hints.append(RoleHint(bucket: "siri", label: "Hey Siri Listener", reason: "Apple device Hey Siri voice trigger", weight: 6))
                case 0x09:
                    hints.append(RoleHint(bucket: "audio-speaker", label: "AirPlay / Apple TV", reason: "AirPlay audio or video receiver", weight: 6))
                case 0x0B:
                    hints.append(RoleHint(bucket: "phone", label: "Apple Handoff", reason: "Continuity Handoff sync broadcast", weight: 5))
                case 0x0C, 0x0D, 0x0E:
                    hints.append(RoleHint(bucket: "hotspot", label: "Instant Hotspot", reason: "iPhone/iPad tethering broadcast", weight: 6))
                case 0x10:
                    hints.append(RoleHint(bucket: "phone", label: "Nearby Info", reason: "Apple ecosystem continuity status", weight: 4))
                case 0x12:
                    hints.append(RoleHint(bucket: "finder", label: "Apple Find My / AirTag", reason: "Offline finding beacon payload", weight: 10))
                default:
                    break
                }
            }
        }
        
        // 2. Check Fast Pair
        for rec in sighting.facts.serviceDataRecords where rec.uuid.uppercased().contains("FE2C") {
            hints.append(RoleHint(bucket: "finder", label: "Google Fast Pair", reason: "Android proximity pairing / Find My Device", weight: 8))
        }
        
        // 3. Check Eddystone
        for rec in sighting.facts.serviceDataRecords where rec.uuid.uppercased().contains("FEAA") {
            hints.append(RoleHint(bucket: "beacon", label: "Eddystone Beacon", reason: "Google Eddystone open beacon format", weight: 7))
        }
        
        // 4. Check Flipper Zero
        if let name = sighting.name?.lowercased(), name.contains("flipper") {
            hints.append(RoleHint(bucket: "hacking", label: "Flipper Zero", reason: "Pen-testing / multi-tool device detected", weight: 10))
        }
        
        // 5. Check OpenDroneID
        if sighting.facts.openDroneIdPayload != nil || sighting.facts.serviceUuids.contains(where: { $0.contains("FFFA") }) {
            hints.append(RoleHint(bucket: "drone", label: "Remote ID Drone", reason: "FAA / EASA OpenDroneID broadcast", weight: 10))
        }
        
        return hints.sorted { $0.weight > $1.weight }
    }
    
    // MARK: - Apple Protocol Decoder
    public struct AppleTLV {
        public let type: UInt8
        public let data: Data
    }
    
    public static func parseAppleTLVs(data: Data) -> [AppleTLV] {
        var tlvs: [AppleTLV] = []
        var offset = 0
        while offset + 1 < data.count {
            let type = data[offset]
            let len = Int(data[offset + 1])
            offset += 2
            guard offset + len <= data.count else { break }
            let chunk = data.subdata(in: offset..<(offset + len))
            tlvs.append(AppleTLV(type: type, data: chunk))
            offset += len
        }
        return tlvs
    }
    
    private static func decodeApple(data: Data) -> [DecodedField] {
        var fields: [DecodedField] = []
        let tlvs = parseAppleTLVs(data: data)
        for tlv in tlvs {
            switch tlv.type {
            case 0x02: // iBeacon
                if tlv.data.count >= 20 {
                    let uuidData = tlv.data.subdata(in: 0..<16)
                    let major = (UInt16(tlv.data[16]) << 8) | UInt16(tlv.data[17])
                    let minor = (UInt16(tlv.data[18]) << 8) | UInt16(tlv.data[19])
                    let tx = tlv.data.count > 20 ? Int8(bitPattern: tlv.data[20]) : 0
                    fields.append(DecodedField(label: "iBeacon UUID", value: formatUUID(uuidData)))
                    fields.append(DecodedField(label: "iBeacon Major", value: "\(major)"))
                    fields.append(DecodedField(label: "iBeacon Minor", value: "\(minor)"))
                    fields.append(DecodedField(label: "Measured Power @ 1m", value: "\(tx) dBm"))
                }
            case 0x05:
                fields.append(DecodedField(label: "AirDrop", value: "\(tlv.data.count) bytes hash"))
            case 0x07: // AirPods
                if let model = decodeAirPodsModel(data: tlv.data) {
                    fields.append(DecodedField(label: "Proximity Device", value: model))
                }
                if tlv.data.count >= 5 {
                    fields.append(DecodedField(label: "Pairing Status", value: "Raw: 0x\(tlv.data.hexUpper.prefix(10))"))
                }
            case 0x10: // Nearby Info
                if let first = tlv.data.first {
                    let activity = (first & 0xF0) >> 4
                    fields.append(DecodedField(label: "Nearby Info Activity", value: "Code \(activity)"))
                }
            case 0x12: // Find My / AirTag
                if tlv.data.count >= 22 {
                    let status = tlv.data[0]
                    let isSeparated = (status & 0x04) != 0
                    let pubKey = tlv.data.subdata(in: 1..<21).hexUpper
                    fields.append(DecodedField(label: "Find My Status", value: isSeparated ? "Separated from Owner (Tracking)" : "Near Owner"))
                    fields.append(DecodedField(label: "Public Key Prefix", value: String(pubKey.prefix(16)) + "..."))
                }
            default:
                fields.append(DecodedField(label: "Apple TLV 0x\(String(format: "%02X", tlv.type))", value: "\(tlv.data.count) bytes"))
            }
        }
        return fields
    }
    
    private static func decodeAirPodsModel(data: Data) -> String? {
        guard data.count >= 3 else { return nil }
        let modelCode = (UInt16(data[1]) << 8) | UInt16(data[2])
        switch modelCode {
        case 0x0220: return "AirPods 1st Gen"
        case 0x0F20: return "AirPods 2nd Gen"
        case 0x1320: return "AirPods 3rd Gen"
        case 0x0E20: return "AirPods Pro"
        case 0x1420: return "AirPods Pro 2nd Gen"
        case 0x0A20: return "AirPods Max"
        case 0x0520: return "Powerbeats Pro"
        case 0x1020: return "Beats Studio Buds"
        default: return "Apple Audio (0x\(String(format: "%04X", modelCode)))"
        }
    }
    
    // MARK: - Fast Pair Decoder
    private static func decodeFastPair(data: Data) -> [DecodedField] {
        var fields: [DecodedField] = []
        if data.count >= 3 {
            let modelId = String(format: "%02X%02X%02X", data[0], data[1], data[2])
            fields.append(DecodedField(label: "Fast Pair Model ID", value: modelId))
        }
        if data.count > 3 {
            fields.append(DecodedField(label: "Fast Pair Salt/Data", value: data.subdata(in: 3..<data.count).hexUpper))
        }
        return fields
    }
    
    // MARK: - Eddystone Decoder
    private static func decodeEddystone(data: Data) -> [DecodedField] {
        guard let frameType = data.first else { return [] }
        var fields: [DecodedField] = []
        switch frameType {
        case 0x00: // UID
            if data.count >= 18 {
                let namespace = data.subdata(in: 2..<12).hexUpper
                let instance = data.subdata(in: 12..<18).hexUpper
                fields.append(DecodedField(label: "Eddystone UID Namespace", value: namespace))
                fields.append(DecodedField(label: "Eddystone UID Instance", value: instance))
            }
        case 0x10: // URL
            if data.count >= 3 {
                fields.append(DecodedField(label: "Eddystone URL", value: decodeEddystoneUrl(data: data.subdata(in: 2..<data.count))))
            }
        case 0x20: // TLM
            if data.count >= 14 {
                let vbatt = (UInt16(data[2]) << 8) | UInt16(data[3])
                let tempRaw = Int16(bitPattern: (UInt16(data[4]) << 8) | UInt16(data[5]))
                let tempC = Float(tempRaw) / 256.0
                fields.append(DecodedField(label: "Battery Voltage", value: "\(vbatt) mV"))
                fields.append(DecodedField(label: "Beacon Temp", value: String(format: "%.1f °C", tempC)))
            }
        default:
            fields.append(DecodedField(label: "Eddystone Frame", value: "0x\(String(format: "%02X", frameType))"))
        }
        return fields
    }
    
    private static func decodeEddystoneUrl(data: Data) -> String {
        guard let schemeByte = data.first else { return "" }
        let schemes = ["http://www.", "https://www.", "http://", "https://"]
        var url = (schemeByte < schemes.count) ? schemes[Int(schemeByte)] : ""
        let expansions = [
            ".com/", ".org/", ".edu/", ".net/", ".info/", ".biz/", ".gov/",
            ".com", ".org", ".edu", ".net", ".info", ".biz", ".gov"
        ]
        for byte in data.dropFirst() {
            if byte < expansions.count {
                url += expansions[Int(byte)]
            } else {
                let scalar = UnicodeScalar(byte)
                if CharacterSet.alphanumerics.contains(scalar) || byte == 0x2D || byte == 0x2E {
                    url.append(Character(scalar))
                }
            }
        }
        return url
    }
    
    // MARK: - OpenDroneID
    private static func decodeOpenDroneId(data: Data) -> [DecodedField] {
        var fields: [DecodedField] = []
        guard data.count >= 1 else { return [] }
        let header = data[0]
        let msgType = (header & 0xF0) >> 4
        switch msgType {
        case 0x00: // Basic ID
            fields.append(DecodedField(label: "RemoteID Msg", value: "Basic ID"))
            if data.count >= 21 {
                let idType = data[1] & 0x0F
                let uasId = String(data: data.subdata(in: 2..<22), encoding: .ascii) ?? "Unknown"
                fields.append(DecodedField(label: "UAS ID Type", value: "\(idType)"))
                fields.append(DecodedField(label: "UAS Serial/ID", value: uasId.trimmingCharacters(in: .controlCharacters)))
            }
        case 0x01: // Location / Vector
            fields.append(DecodedField(label: "RemoteID Msg", value: "Location / Vector"))
            if data.count >= 17 {
                let latRaw = Int32(bitPattern: (UInt32(data[4]) << 24) | (UInt32(data[5]) << 16) | (UInt32(data[6]) << 8) | UInt32(data[7]))
                let lonRaw = Int32(bitPattern: (UInt32(data[8]) << 24) | (UInt32(data[9]) << 16) | (UInt32(data[10]) << 8) | UInt32(data[11]))
                let lat = Double(latRaw) / 10000000.0
                let lon = Double(lonRaw) / 10000000.0
                fields.append(DecodedField(label: "Drone Coords", value: String(format: "%.6f, %.6f", lat, lon)))
            }
        default:
            fields.append(DecodedField(label: "RemoteID Message Type", value: "Type 0x\(String(format: "%02X", msgType))"))
        }
        return fields
    }
    
    private static func decodeMicrosoft(data: Data) -> [DecodedField] {
        guard let scenario = data.first else { return [] }
        return [
            DecodedField(label: "Microsoft CDP Scenario", value: "0x\(String(format: "%02X", scenario))"),
            DecodedField(label: "Payload Size", value: "\(data.count) bytes")
        ]
    }
    
    private static func decodeAltBeacon(data: Data) -> [DecodedField] {
        guard data.count >= 24 else { return [] }
        let beaconId = data.subdata(in: 2..<22).hexUpper
        let refRssi = Int8(bitPattern: data[22])
        return [
            DecodedField(label: "AltBeacon ID", value: beaconId),
            DecodedField(label: "Reference RSSI @ 1m", value: "\(refRssi) dBm")
        ]
    }
    
    private static func decodeSamsung(data: Data) -> [DecodedField] {
        return [
            DecodedField(label: "Samsung SmartThings", value: "\(data.count) bytes payload")
        ]
    }
    
    private static func formatUUID(_ data: Data) -> String {
        guard data.count == 16 else { return data.hexUpper }
        let h = data.hexUpper
        return "\(h.prefix(8))-\(h.dropFirst(8).prefix(4))-\(h.dropFirst(12).prefix(4))-\(h.dropFirst(16).prefix(4))-\(h.dropFirst(20))"
    }
}

// MARK: - Data Hex Extensions
extension Data {
    public init?(hexString: String) {
        let clean = hexString.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            if let byte = UInt8(clean[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
    
    public var hexUpper: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
