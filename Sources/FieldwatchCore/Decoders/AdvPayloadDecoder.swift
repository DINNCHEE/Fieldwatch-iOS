//
//  AdvPayloadDecoder.swift
//  Fieldwatch
//
//  BLE manufacturer / service-data decoders + role hints.
//  1:1 port of the original AdvPayloadDecoder.
//

import Foundation

public struct AdvPayloadDecoder: Sendable {

    static let teslaIbeaconMfgPrefix = "021574278BDAB64445208F0C720EAF059935"
    static let targetAtriusIbeaconMfgPrefix = "02155993A94C7D974DF79ABFE493BFD5D000"

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
        case 0x00E0: // Google
            return [DecodedField(label: "Google manufacturer data", value: "\(data.count) bytes")]
        default:
            return []
        }
    }

    // MARK: - Decoded Service Data Payload
    public static func decodeService(record: ServiceDataRecord) -> [DecodedField] {
        guard let data = Data(hexString: record.dataHex),
              let short = DeviceExplain.uuid16(record.uuid) else { return [] }
        switch short {
        case 0xFE2C:
            return decodeFastPair(data: data)
        case 0xFEAA:
            return decodeEddystone(data: data)
        case 0xFFFA:
            // Improvement over stock: ASTM Remote ID service data.
            return decodeOpenDroneId(data: data)
        default:
            return []
        }
    }

    // MARK: - Spam / flood signatures (Wall-of-Flippers style prefixes, _ = wildcard)
    // Full hex = company ID (4 hex) + manufacturer payload, or service UUID + data.
    private static let spamTable: [(pattern: String, label: String, weight: Int)] = [
        ("4C000719010_2055", "AppleJuice popup-close spam", 10),
        ("4C000F05C00", "Apple action-modal spam", 10),
        ("4C00071907", "Apple connect spam", 9),
        ("4C0004042A0000000F05C1__604C950", "Apple setup spam", 10),
        ("2CFE", "SwiftPair / Android Nearby spam", 9),
        ("750042098102141503210109____01_", "Samsung Buds spam", 9),
        ("7500010002000101FF000043", "Samsung Watch spam", 9),
        ("0600030080", "Windows Swift Pair spam", 9),
        ("00001812", "HID flood spam", 8),
        ("FF006DB643CE97FE427C", "LoveSpouse spam", 9),
        ("00003081", "Flipper Zero Black spam", 8),
        ("00003082", "Flipper Zero White spam", 8),
        ("00003083", "Flipper Zero Transparent spam", 8),
    ]

    private static func matchesSpam(pattern: String, hex: String) -> Bool {
        guard hex.count >= pattern.count else { return false }
        let h = hex.uppercased()
        let p = pattern.uppercased()
        for (pc, hc) in zip(p, h) {
            if pc == "_" { continue }
            if pc != hc { return false }
        }
        return true
    }

    public static func spamHints(mfgFullHex: [String], serviceFullHex: [String]) -> [RoleHint] {
        var out: [RoleHint] = []
        let all = mfgFullHex + serviceFullHex
        for (pattern, label, weight) in spamTable {
            for hex in all where matchesSpam(pattern: pattern, hex: hex) {
                out.append(RoleHint(bucket: "spam", label: label,
                    reason: "Known spam / flood advertisement signature.", weight: weight))
                break
            }
        }
        return out
    }

    // MARK: - Role Hints & Device Profiling
    public static func roleHints(for sighting: Sighting) -> [RoleHint] {
        var hints: [RoleHint] = []

        // 0. Spam / flood check first (highest confidence nuisance)
        let mfgFull = sighting.facts.mfgRecords.map {
            String(format: "%04X", $0.companyId) + $0.dataHex
        }
        let svcFull = sighting.facts.serviceDataRecords.map {
            $0.uuid.replacingOccurrences(of: "-", with: "") + $0.dataHex
        } + sighting.facts.serviceUuids.map {
            $0.replacingOccurrences(of: "-", with: "")
        }
        hints += spamHints(mfgFullHex: mfgFull, serviceFullHex: svcFull)

        for rec in sighting.facts.mfgRecords where rec.companyId == 0x004C {
            guard let data = Data(hexString: rec.dataHex) else { continue }
            for tlv in parseAppleTLVs(data: data) {
                switch tlv.type {
                case 0x02:
                    if tlv.data.count >= 20 {
                        let hex = tlv.data.hexUpper
                        if hex.hasPrefix(teslaIbeaconMfgPrefix) || hex.hasPrefix(String(teslaIbeaconMfgPrefix.dropFirst(4))) {
                            hints.append(RoleHint(bucket: "vehicle", label: "a Tesla vehicle or phone-as-key", reason: "Tesla phone-key iBeacon UUID (iOS background find).", weight: 8))
                        } else if hex.hasPrefix(targetAtriusIbeaconMfgPrefix) || hex.hasPrefix(String(targetAtriusIbeaconMfgPrefix.dropFirst(4))) {
                            hints.append(RoleHint(bucket: "beacon", label: "a Target Atrius basket tag", reason: "Target / Atrius iBeacon UUID (shopping-basket asset tag).", weight: 8))
                        } else {
                            hints.append(RoleHint(bucket: "beacon", label: "an iBeacon", reason: "Apple iBeacon payload.", weight: 7))
                        }
                    }
                case 0x05:
                    hints.append(RoleHint(bucket: "phone", label: "an iPhone or iPad offering AirDrop", reason: "Apple AirDrop advertisement.", weight: 5))
                case 0x07:
                    let model = decodeAirPodsModelName(data: tlv.data)
                    if let model = model {
                        hints.append(RoleHint(bucket: "audio-personal", label: model, reason: "Apple Proximity Pairing: \(model).", weight: 8))
                    } else {
                        hints.append(RoleHint(bucket: "audio-personal", label: "AirPods or Beats headphones", reason: "Apple Proximity Pairing (AirPods / Beats).", weight: 8))
                    }
                case 0x08:
                    hints.append(RoleHint(bucket: "siri", label: "an Apple device that just heard “Hey Siri”", reason: "Hey Siri advertisement.", weight: 6))
                case 0x09:
                    hints.append(RoleHint(bucket: "audio-speaker", label: "an AirPlay speaker or Apple TV", reason: "AirPlay advertisement.", weight: 5))
                case 0x0B:
                    hints.append(RoleHint(bucket: "phone", label: "an Apple device doing Handoff", reason: "Handoff advertisement.", weight: 4))
                case 0x0C:
                    hints.append(RoleHint(bucket: "phone", label: "an Apple device looking for Instant Hotspot", reason: "Tethering-target advertisement.", weight: 5))
                case 0x0D, 0x0E:
                    hints.append(RoleHint(bucket: "hotspot", label: "an iPhone/iPad offering Instant Hotspot", reason: "Tethering-source advertisement.", weight: 6))
                case 0x0F:
                    hints.append(RoleHint(bucket: "phone", label: "an Apple device (Nearby Action)", reason: nearbyActionReason(data: tlv.data), weight: 4))
                case 0x10:
                    hints.append(RoleHint(bucket: "phone", label: "an iPhone / iPad / Mac (Nearby Info)", reason: nearbyInfoReason(data: tlv.data), weight: 5))
                case 0x12:
                    hints.append(RoleHint(bucket: "tag", label: "a Find My network radio", reason: "Apple Offline Finding — AirTag, Find My accessory, or an Apple device locating itself.", weight: 4))
                default:
                    break
                }
            }
        }

        for sdata in sighting.facts.serviceDataRecords {
            guard let short = DeviceExplain.uuid16(sdata.uuid) else { continue }
            switch short {
            case 0xFE2C:
                guard let data = Data(hexString: sdata.dataHex) else { continue }
                if data.count == 3 {
                    let id = (Int(data[0]) << 16) | (Int(data[1]) << 8) | Int(data[2])
                    if let name = FastPairModels.name(modelId: id) {
                        hints.append(RoleHint(bucket: "audio-personal", label: name, reason: "Google Fast Pair model \(name) (0x\(String(format: "%06X", id))), in pairing mode.", weight: 8))
                    } else {
                        hints.append(RoleHint(bucket: "audio-personal", label: "a Fast Pair accessory (often earbuds or a speaker)", reason: "Google Fast Pair model 0x\(String(format: "%06X", id)), in pairing mode.", weight: 6))
                    }
                } else {
                    hints.append(RoleHint(bucket: "audio-personal", label: "a Fast Pair accessory already paired to someone", reason: "Google Fast Pair account-key broadcast (not in pairing mode).", weight: 4))
                }
            case 0xFEAA:
                guard let data = Data(hexString: sdata.dataHex), let first = data.first else { continue }
                if first == 0x40 || first == 0x41 {
                    hints.append(RoleHint(bucket: "tag", label: "a Google Find Hub tag", reason: first == 0x41 ? "Find Hub separated (unwanted-tracking) frame." : "Find Hub nearby frame.", weight: 8))
                } else {
                    hints.append(RoleHint(bucket: "beacon", label: "an Eddystone beacon", reason: "Eddystone service data.", weight: 6))
                }
            default:
                break
            }
        }

        // 3. Setup-mode cameras + OBD dongles by advertised name
        let lname = (sighting.name ?? "").lowercased()
        if !lname.isEmpty {
            let setupCamPrefixes = ["mv_", "mv+", "xmeye_ap", "cam_", "dog-", "360_", "tp-link_"]
            if setupCamPrefixes.contains(where: { lname.hasPrefix($0) }) {
                hints.append(RoleHint(bucket: "camera", label: "kurulum modunda kamera (açık hotspot)", reason: "Setup SSID kalıbı; kameranın kurulum ağı açık.", weight: 7))
            }
            let obdKeys = ["v-link", "vlink", "ios-vlink", "dszm", "obdii", "obd2wifi", "elm327", "viecar", "torque"]
            if obdKeys.contains(where: { lname.contains($0) }) {
                hints.append(RoleHint(bucket: "vehicle", label: "OBD-II dongle", reason: "Araç arıza/diagnostic adaptörü yayını.", weight: 7))
            }
            if lname.contains("flipper") {
                hints.append(RoleHint(bucket: "hacking", label: "Flipper Zero", reason: "Pen-test çoklu aracı.", weight: 8))
            }
        }

        return hints
    }

    // MARK: - Apple Protocol Decoder
    public struct AppleTLV {
        public let type: UInt8
        public let data: Data
    }

    public static func parseAppleTLVs(data: Data) -> [AppleTLV] {
        var tlvs: [AppleTLV] = []
        var i = 0
        while i + 2 <= data.count {
            let type = data[i]
            let len = Int(data[i + 1])
            if len <= 0 || i + 2 + len > data.count { break }
            tlvs.append(AppleTLV(type: type, data: data.subdata(in: (i + 2)..<(i + 2 + len))))
            i += 2 + len
        }
        return tlvs
    }

    private static func appleTypeName(_ type: UInt8) -> String {
        switch type {
        case 0x02: return "iBeacon"
        case 0x03: return "AirPrint"
        case 0x05: return "AirDrop"
        case 0x06: return "HomeKit"
        case 0x07: return "Proximity Pairing (AirPods / Beats)"
        case 0x08: return "Hey Siri"
        case 0x09: return "AirPlay"
        case 0x0A: return "Magic Switch (Watch)"
        case 0x0B: return "Handoff"
        case 0x0C: return "Handoff or Instant Hotspot (target)"
        case 0x0D: return "Instant Hotspot (source)"
        case 0x0E: return "Instant Hotspot (source)"
        case 0x0F: return "Nearby Action"
        case 0x10: return "Nearby Info"
        case 0x12: return "Find My / Offline Finding"
        case 0x13: return "Nearby Action (extended)"
        case 0x16: return "Nearby Info"
        default: return "unlisted"
        }
    }

    private static func decodeApple(data: Data) -> [DecodedField] {
        let tlvs = parseAppleTLVs(data: data)
        if tlvs.isEmpty {
            return [DecodedField(label: "Apple payload", value: "\(data.count) bytes (unparsed)")]
        }
        var fields: [DecodedField] = []
        for tlv in tlvs {
            fields.append(DecodedField(label: "Apple Continuity type", value: String(format: "0x%02X · %@", tlv.type, appleTypeName(tlv.type))))
            switch tlv.type {
            case 0x02: fields += decodeIBeacon(data: tlv.data)
            case 0x05: fields += decodeAirDrop(data: tlv.data)
            case 0x06: fields.append(DecodedField(label: "HomeKit", value: "\(tlv.data.count) bytes of HomeKit setup data"))
            case 0x07: fields += decodeAirPods(data: tlv.data)
            case 0x08: fields += decodeHeySiri(data: tlv.data)
            case 0x09: fields.append(DecodedField(label: "AirPlay", value: "This device is advertising as an AirPlay source or target."))
            case 0x0A: fields.append(DecodedField(label: "Magic Switch", value: "Apple Watch wrist / unlock related."))
            case 0x0B: fields += decodeHandoff(data: tlv.data)
            case 0x0C: fields += decodeHandoffOrTetherTarget(data: tlv.data)
            case 0x0D, 0x0E: fields += decodeTetherSource(data: tlv.data)
            case 0x0F: fields += decodeNearbyAction(data: tlv.data)
            case 0x10: fields += decodeNearbyInfo(data: tlv.data)
            case 0x12: fields += decodeFindMy(data: tlv.data)
            default: fields.append(DecodedField(label: "Payload", value: "\(tlv.data.count) bytes"))
            }
        }
        return fields
    }

    private static func decodeIBeacon(data: Data) -> [DecodedField] {
        let body: Data
        if data.count >= 22 && data[0] == 0x15 {
            body = data.subdata(in: 1..<22)
        } else if data.count >= 21 {
            body = data.subdata(in: 0..<21)
        } else {
            return [DecodedField(label: "iBeacon", value: "truncated (\(data.count) bytes)")]
        }
        let uuid = formatUUID(body.subdata(in: 0..<16))
        let major = (Int(body[16]) << 8) | Int(body[17])
        let minor = (Int(body[18]) << 8) | Int(body[19])
        let tx = Int(Int8(bitPattern: body[20]))
        let hex = body.hexUpper
        let teslaKey = hex.hasPrefix(teslaIbeaconMfgPrefix) || hex.hasPrefix(String(teslaIbeaconMfgPrefix.dropFirst(4)))
        return [
            DecodedField(label: "iBeacon UUID", value: teslaKey ? "\(uuid) — Tesla phone-as-key (iOS background find). Not a mall beacon." : uuid),
            DecodedField(label: "iBeacon major / minor", value: "\(major) / \(minor)"),
            DecodedField(label: "iBeacon calibrated TX", value: "\(tx) dBm at 1 m (used to estimate range)")
        ]
    }

    private static func decodeAirDrop(data: Data) -> [DecodedField] {
        if data.count < 18 {
            return [DecodedField(label: "AirDrop", value: "Someone nearby is offering AirDrop (\(data.count) bytes).")]
        }
        return [
            DecodedField(label: "AirDrop", value: "Someone nearby has AirDrop receiving on. Hashes are truncated IDs, not names."),
            DecodedField(label: "Apple ID hash (2 bytes)", value: data.subdata(in: 9..<11).hexUpper)
        ]
    }

    private static func decodeAirPods(data: Data) -> [DecodedField] {
        if data.count < 5 { return [DecodedField(label: "AirPods", value: "Proximity Pairing, truncated.")] }
        let start = (data[0] == 0x01) ? 1 : 0
        if data.count < start + 4 { return [DecodedField(label: "AirPods", value: "Proximity Pairing.")] }
        let model = (Int(data[start]) << 8) | Int(data[start + 1])
        let status = Int(data[start + 2])
        let batt = Int(data[start + 3])
        let left = batt & 0x0F
        let right = (batt >> 4) & 0x0F
        var out: [DecodedField] = []
        out.append(DecodedField(label: "Product", value: airPodsModelName(id: model) ?? String(format: "Apple audio 0x%04X", model)))
        out.append(DecodedField(label: "Pod position", value: airPodsStatus(status: status)))
        out.append(DecodedField(label: "Battery (left / right)", value: "\(nibblePct(left)) / \(nibblePct(right))"))
        if data.count > start + 4 {
            let ch = Int(data[start + 4])
            let caseBatt = ch & 0x0F
            var charging: [String] = []
            if ch & 0x10 != 0 { charging.append("case") }
            if ch & 0x20 != 0 { charging.append("right") }
            if ch & 0x40 != 0 { charging.append("left") }
            out.append(DecodedField(label: "Case battery", value: nibblePct(caseBatt)))
            if !charging.isEmpty { out.append(DecodedField(label: "Charging", value: charging.joined(separator: ", "))) }
        }
        if data.count > start + 6 {
            out.append(DecodedField(label: "Color", value: airPodsColor(v: Int(data[start + 6]))))
        }
        return out
    }

    private static func decodeAirPodsModelName(data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let start = (data[0] == 0x01) ? 1 : 0
        guard data.count >= start + 2 else { return nil }
        let model = (Int(data[start]) << 8) | Int(data[start + 1])
        return airPodsModelName(id: model)
    }

    private static func airPodsModelName(id: Int) -> String? {
        switch id {
        case 0x0220: return "AirPods (1st generation)"
        case 0x0F20: return "AirPods (2nd generation)"
        case 0x1320: return "AirPods (3rd generation)"
        case 0x1920: return "AirPods (4th generation)"
        case 0x1C20: return "AirPods 4"
        case 0x0E20: return "AirPods Pro"
        case 0x1420: return "AirPods Pro (2nd generation)"
        case 0x2420: return "AirPods Pro 2 (USB-C)"
        case 0x1F20: return "AirPods Max"
        case 0x0A20: return "Beats Solo3"
        case 0x0B20: return "Powerbeats 3"
        case 0x0C20: return "Beats Studio Buds"
        case 0x0D20: return "Beats Fit Pro"
        case 0x1020: return "Powerbeats Pro"
        case 0x1120: return "Beats Studio Buds +"
        case 0x1220: return "Beats Solo Pro"
        case 0x1720: return "Beats Flex"
        case 0x1A20: return "Beats Studio Pro"
        case 0x1B20: return "Beats Fit Pro"
        case 0x0520: return "BeatsX"
        case 0x0920: return "Beats Studio³ Wireless"
        case 0x1620: return "Beats Studio Buds +"
        case 0x2520: return "Beats Solo 4"
        case 0x2620: return "Beats Solo Buds"
        case 0x2D20: return "AirPods Max 2"
        case 0x3820: return "Beats 360"
        case 0x038F: return "Beats Studio Buds"
        default: return nil
        }
    }

    private static func airPodsStatus(status: Int) -> String {
        switch status {
        case 0x01: return "One or both out of the case"
        case 0x02: return "Case open"
        case 0x03: return "Taken out / in-ear transition"
        case 0x05: return "One in ear"
        case 0x09: return "Both out, not in ear"
        case 0x0B: return "In-ear activity"
        case 0x11, 0x13: return "Both in ear"
        case 0x21: return "One in ear (sharing?)"
        case 0x51: return "Both in case, lid open"
        case 0x55: return "Both in case, lid closed"
        case 0x75: return "In case"
        default: return String(format: "Status 0x%02X", status)
        }
    }

    private static func airPodsColor(v: Int) -> String {
        switch v {
        case 0x00: return "White"
        case 0x01: return "Black"
        case 0x02: return "Red"
        case 0x03: return "Blue"
        case 0x04: return "Pink"
        case 0x05: return "Gray"
        case 0x06: return "Silver"
        case 0x07: return "Gold"
        case 0x08: return "Rose gold"
        case 0x09: return "Space gray"
        case 0x0A: return "Dark blue"
        case 0x0B: return "Light blue"
        case 0x0C: return "Yellow"
        default: return String(format: "0x%02X", v)
        }
    }

    private static func nibblePct(_ n: Int) -> String {
        switch n {
        case 0...9: return "\(n * 10)%"
        case 10, 11, 12, 13, 14: return "100%"
        case 15: return "unknown / not present"
        default: return "\(n)"
        }
    }

    private static func decodeHeySiri(data: Data) -> [DecodedField] {
        if data.count < 6 {
            return [DecodedField(label: "Hey Siri", value: "Siri was just triggered on a nearby Apple device.")]
        }
        let klass = (Int(data[4]) << 8) | Int(data[5])
        let device: String
        switch klass {
        case 0x0002: device = "iPhone"
        case 0x0003: device = "iPad"
        case 0x0007: device = "HomePod"
        case 0x0009: device = "Mac"
        case 0x000A: device = "Watch"
        default: device = String(format: "class 0x%04X", klass)
        }
        return [DecodedField(label: "Hey Siri", value: "A \(device) just heard a Siri trigger. The packet carries a short voice hash, not the words.")]
    }

    private static func decodeHandoff(data: Data) -> [DecodedField] {
        [DecodedField(label: "Handoff", value: "Continuity Handoff: a task can be continued on another Apple device. Payload is encrypted.")]
    }

    private static func decodeHandoffOrTetherTarget(data: Data) -> [DecodedField] {
        if data.count >= 14 { return decodeHandoff(data: data) }
        return [DecodedField(label: "Instant Hotspot (looking)", value: "This Apple device is searching for a paired phone’s hotspot.")]
    }

    private static func decodeTetherSource(data: Data) -> [DecodedField] {
        if data.count < 6 {
            return [DecodedField(label: "Instant Hotspot", value: "An iPhone/iPad is offering a personal hotspot.")]
        }
        let batt = Int(data[2])
        let cell = data.count >= 5 ? (Int(data[3]) << 8) | Int(data[4]) : -1
        let bars = data.count >= 6 ? Int(data[5]) : -1
        let cellName: String?
        switch cell {
        case 0, 6: cellName = "4G"
        case 1: cellName = "1xRTT"
        case 2: cellName = "GPRS"
        case 3: cellName = "EDGE"
        case 4, 5: cellName = "3G"
        case 7: cellName = "LTE"
        case 8: cellName = "5G"
        default: cellName = cell >= 0 ? "type \(cell)" : nil
        }
        var parts = "Paired iPhone/iPad hotspot"
        if (0...100).contains(batt) { parts += " · phone battery \(batt)%" }
        if let cellName = cellName { parts += " · \(cellName)" }
        if (0...5).contains(bars) { parts += " · \(bars)/5 bars" }
        return [DecodedField(label: "Instant Hotspot (offering)", value: parts)]
    }

    private static func decodeNearbyAction(data: Data) -> [DecodedField] {
        if data.isEmpty { return [DecodedField(label: "Nearby Action", value: "Apple Nearby Action")] }
        let action = data.count >= 2 ? Int(data[1]) : Int(data[0])
        return [DecodedField(label: "Nearby Action", value: nearbyActionName(action: action))]
    }

    static func nearbyActionReason(data: Data) -> String {
        guard data.count >= 2 else { return "Nearby Action advertisement." }
        return "Nearby Action: \(nearbyActionName(action: Int(data[1])))."
    }

    private static func nearbyActionName(action: Int) -> String {
        switch action {
        case 0x01: return "Apple TV setup"
        case 0x04: return "Mobile backup"
        case 0x05: return "Watch setup"
        case 0x06: return "Apple TV pair"
        case 0x08: return "Wi-Fi password sharing (prompting nearby iPhones)"
        case 0x09: return "iOS setup"
        case 0x0A: return "Repair"
        case 0x0B: return "Speaker setup"
        case 0x0C: return "Apple Pay"
        case 0x0D: return "Whole-home audio setup"
        case 0x0F: return "Answered a call"
        case 0x10: return "Ended a call"
        case 0x13: return "Remote AutoFill"
        case 0x14: return "Companion Link proximity"
        case 0x17: return "Remote display"
        default: return String(format: "action 0x%02X", action)
        }
    }

    private static func decodeNearbyInfo(data: Data) -> [DecodedField] {
        if data.isEmpty { return [DecodedField(label: "Nearby Info", value: "Apple device usage state.")] }
        let status = Int(data[0])
        let action = status & 0x0F
        let flagsHi = (status >> 4) & 0x0F
        let dataFlags = data.count > 1 ? Int(data[1]) : 0
        let activity: String
        switch action {
        case 0x00: activity = "activity unknown"
        case 0x01: activity = "activity reporting off"
        case 0x03: activity = "idle (screen locked)"
        case 0x05: activity = "audio playing, screen locked"
        case 0x07: activity = "active (screen on)"
        case 0x09: activity = "screen on, video playing"
        case 0x0A: activity = "Watch on wrist and unlocked"
        case 0x0B: activity = "recent interaction"
        case 0x0D: activity = "user is driving"
        case 0x0E: activity = "phone or FaceTime call"
        default: activity = String(format: "activity 0x%X", action)
        }
        var extras: [String] = []
        if flagsHi & 0x1 != 0 { extras.append("primary iCloud device") }
        if flagsHi & 0x4 != 0 { extras.append("AirDrop receiving on") }
        if dataFlags & 0x04 != 0 { extras.append("Wi-Fi on") }
        if dataFlags & 0x01 != 0 { extras.append("AirPods connected") }
        if dataFlags & 0x20 != 0 { extras.append("Watch locked") }
        var text = activity.prefix(1).uppercased() + String(activity.dropFirst())
        if !extras.isEmpty { text += ". " + extras.joined(separator: "; ") }
        text += "."
        return [DecodedField(label: "What the Apple device is doing", value: text)]
    }

    static func nearbyInfoReason(data: Data) -> String {
        guard !data.isEmpty else { return "Nearby Info advertisement." }
        switch Int(data[0]) & 0x0F {
        case 0x03: return "Phone is idle / locked."
        case 0x05: return "Audio playing with the screen locked."
        case 0x07: return "Screen is on — someone is using it."
        case 0x0D: return "Device reports the user is driving."
        case 0x0E: return "In a phone or FaceTime call."
        default: return "Nearby Info advertisement."
        }
    }

    private static func decodeFindMy(data: Data) -> [DecodedField] {
        if data.isEmpty { return [DecodedField(label: "Find My", value: "Offline Finding advertisement.")] }
        let status = Int(data[0])
        let maintained = status & 0x04 != 0
        let batt = (status >> 6) & 0x3
        let battName: String
        switch batt {
        case 0: battName = "full"
        case 1: battName = "medium"
        case 2: battName = "low"
        default: battName = "critical"
        }
        let keyLen = max(0, data.count - 1)
        var text = "Broadcasting a public key so the Find My network can report a location. "
        text += "Used by AirTags, Find My accessories, and Apple devices locating themselves. "
        text += maintained ? "Owner seen recently. " : "Owner not seen in the current key window. "
        if maintained || (0...3).contains(batt) { text += "Battery \(battName). " }
        text += "(\(keyLen)-byte key fragment — not a serial number.)"
        return [DecodedField(label: "Find My / Offline Finding", value: text)]
    }

    // MARK: - Fast Pair Decoder (shape handled by FastPair; fields here)
    private static func decodeFastPair(data: Data) -> [DecodedField] {
        if data.count == 3 {
            let id = (Int(data[0]) << 16) | (Int(data[1]) << 8) | Int(data[2])
            let name = FastPairModels.name(modelId: id)
            var fields = [DecodedField(label: "Google Fast Pair", value: "In pairing mode — Android will pop a tap-to-pair card.")]
            if let name = name {
                fields.append(DecodedField(label: "Model ID", value: "\(name)  (0x\(String(format: "%06X", id)))"))
            } else {
                fields.append(DecodedField(label: "Model ID", value: "0x\(String(format: "%06X", id)) (not in the local name list)"))
            }
            return fields
        }
        if data.isEmpty { return [] }
        let verFlags = Int(data[0])
        let version = (verFlags >> 4) & 0x0F
        var ui = "account-key bloom filter"
        if data.count > 1 {
            switch Int(data[1]) & 0x0F {
            case 0x0: ui = "wants to show a pairing card"
            case 0x2: ui = "hiding the pairing card (e.g. buds back in the case)"
            default: ui = "filter type \(Int(data[1]) & 0x0F)"
            }
        }
        return [DecodedField(label: "Google Fast Pair", value: "Already paired to an account (not in pairing mode). \(ui). Version \(version).")]
    }

    // MARK: - Eddystone Decoder
    private static func decodeEddystone(data: Data) -> [DecodedField] {
        guard let frameType = data.first else { return [] }
        switch frameType {
        case 0x00:
            if data.count < 18 { return [DecodedField(label: "Eddystone-UID", value: "truncated")] }
            return [
                DecodedField(label: "Eddystone-UID namespace", value: data.subdata(in: 2..<12).hexUpper),
                DecodedField(label: "Eddystone-UID instance", value: data.subdata(in: 12..<18).hexUpper)
            ]
        case 0x10:
            return [DecodedField(label: "Eddystone-URL", value: decodeEddystoneUrl(data: data) ?? "\(data.count) bytes")]
        case 0x20:
            return [DecodedField(label: "Eddystone-TLM", value: "telemetry (battery / temperature / advert count)")]
        case 0x30:
            return [DecodedField(label: "Eddystone-EID", value: "ephemeral ID (rotating)")]
        case 0x40, 0x41:
            let mode = frameType == 0x41 ? "separated (unwanted-tracking mode)" : "nearby / with owner"
            let eidLen: Int
            if data.count >= 33 { eidLen = 32 }
            else if data.count >= 21 { eidLen = 20 }
            else { eidLen = max(0, data.count - 1) }
            let eid = eidLen > 0 ? data.subdata(in: 1..<(1 + eidLen)).hexUpper : ""
            return [
                DecodedField(label: "Find Hub", value: mode),
                DecodedField(label: "Find Hub EID", value: eid.isEmpty ? "\(data.count) bytes" : eid)
            ]
        default:
            return [DecodedField(label: "Eddystone", value: String(format: "frame 0x%02X", frameType))]
        }
    }

    private static func decodeEddystoneUrl(data: Data) -> String? {
        if data.count < 3 { return nil }
        let scheme: String
        switch data[2] {
        case 0: scheme = "http://www."
        case 1: scheme = "https://www."
        case 2: scheme = "http://"
        case 3: scheme = "https://"
        default: return nil
        }
        let expansions = [
            ".com/", ".org/", ".edu/", ".net/", ".info/", ".biz/", ".gov/",
            ".com", ".org", ".edu", ".net", ".info", ".biz", ".gov"
        ]
        var url = scheme
        for byte in data.dropFirst(3) {
            let b = Int(byte)
            if b < expansions.count {
                url += expansions[b]
            } else if (0x20...0x7E).contains(b), let scalar = UnicodeScalar(b) {
                url.append(Character(scalar))
            }
        }
        return url
    }

    // MARK: - OpenDroneID (iOS improvement: ASTM Remote ID service data)
    private static func decodeOpenDroneId(data: Data) -> [DecodedField] {
        var fields: [DecodedField] = []
        guard data.count >= 1 else { return [] }
        let header = data[0]
        let msgType = (header & 0xF0) >> 4
        switch msgType {
        case 0x00: // Basic ID
            fields.append(DecodedField(label: "RemoteID Msg", value: "Basic ID"))
            if data.count >= 22 {
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
        if data.isEmpty { return [] }
        if data[0] == 0x01 && data.count >= 2 {
            let type = Int(data[1]) & 0x1F
            let kind: String
            switch type {
            case 1: kind = "Xbox"
            case 6: kind = "iPhone"
            case 7: kind = "iPad"
            case 8: kind = "Android"
            case 9: kind = "Windows desktop"
            case 11: kind = "Windows phone"
            case 12: kind = "Linux"
            case 13: kind = "Windows IoT"
            case 14: kind = "Surface Hub"
            case 15: kind = "Windows laptop"
            case 16: kind = "Windows tablet"
            default: kind = "type \(type)"
            }
            return [DecodedField(label: "Microsoft Nearby Sharing / Swift Pair", value: "A \(kind) is advertising for quick pairing or sharing.")]
        }
        return [DecodedField(label: "Microsoft manufacturer data", value: "\(data.count) bytes")]
    }

    private static func decodeAltBeacon(data: Data) -> [DecodedField] {
        if data.count >= 22 && data[0] == 0xBE && data[1] == 0xAC {
            return [
                DecodedField(label: "AltBeacon UUID", value: formatUUID(data.subdata(in: 2..<18))),
                DecodedField(label: "AltBeacon major / minor", value: "\((Int(data[18]) << 8) | Int(data[19])) / \((Int(data[20]) << 8) | Int(data[21]))")
            ]
        }
        return []
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
        let clean = hexString.filter { $0.isLetter || $0.isNumber }
        guard !clean.isEmpty, clean.count % 2 == 0 else { return nil }
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
