//
//  DeviceExplain.swift
//  Fieldwatch
//
//  Plain-language identity guess. Port of the original DeviceExplain:
//  what the radio is broadcasting, not a visual identification.
//

import Foundation

public struct DeviceGuess: Sendable {
    public enum Confidence: String, Sendable { case high = "HIGH", medium = "MEDIUM", low = "LOW" }
    public let headline: String
    public let because: String
    public let confidence: Confidence
}

private struct ExHint {
    let bucket: String
    let label: String
    let reason: String
    let weight: Int
}

public struct DeviceExplain: Sendable {

    public static func guess(sighting: Sighting, signatureNames: [String] = []) -> DeviceGuess {
        var hints: [ExHint] = []
        let uuids = sighting.facts.serviceUuids + sighting.facts.serviceDataRecords.map { $0.uuid }
        hints += uuidHints(uuids: uuids)
        hints += AdvPayloadDecoder.roleHints(for: sighting).map {
            ExHint(bucket: $0.bucket, label: $0.label, reason: $0.reason, weight: $0.weight)
        }
        hints += signatureHints(names: signatureNames)
        if sighting.kind == .wifi { hints += wifiHints(sighting: sighting, signatureNames: signatureNames) }

        if hints.isEmpty {
            return DeviceGuess(
                headline: sighting.kind == .wifi ? "Wi-Fi access point" : "Bluetooth LE advertiser",
                because: "It is on the air, but it did not advertise a product class " +
                    "(no well-known service, decoded payload, or matching signature).",
                confidence: .low
            )
        }
        var grouped: [String: ExHint] = [:]
        for h in hints.sorted(by: { $0.weight > $1.weight }) {
            if let prev = grouped[h.bucket] {
                if h.weight > prev.weight { grouped[h.bucket] = h }
            } else {
                grouped[h.bucket] = h
            }
        }
        let best = grouped.values.max(by: { $0.weight < $1.weight })!
        var seen: [String] = []
        for h in grouped.values where h.bucket == best.bucket || h.weight >= 3 {
            if !seen.contains(h.reason) { seen.append(h.reason) }
        }
        let confidence: DeviceGuess.Confidence =
            best.weight >= 6 ? .high : (best.weight >= 3 ? .medium : .low)
        let hedge: String
        switch confidence {
        case .high: hedge = "Most likely"
        case .medium: hedge = "Probably"
        case .low: hedge = "Could be"
        }
        return DeviceGuess(
            headline: "\(hedge) \(best.label)",
            because: seen.joined(separator: " ") + " This is what the device is advertising, not a visual ID.",
            confidence: confidence
        )
    }

    /// Compact list title from the same guess. Nil when only generic.
    public static func listLabel(sighting: Sighting, signatureNames: [String] = []) -> String? {
        let g = guess(sighting: sighting, signatureNames: signatureNames)
        let generic = g.headline.localizedCaseInsensitiveContains("Bluetooth LE advertiser") ||
            g.headline.localizedCaseInsensitiveContains("Wi-Fi access point")
        let core = generic ? nil : tidyHeadline(g.headline)
        let vendor = sighting.vendor?.trimmingCharacters(in: .whitespaces).prefix(24).description
            .trimmingCharacters(in: .whitespaces)
        let vendorClean = (vendor?.isEmpty == false) ? vendor : nil
        if let core = core {
            if let v = vendorClean, !core.localizedCaseInsensitiveContains(v) {
                return "\(v) · \(core)"
            }
            return core
        }
        if let v = vendorClean { return "\(v) device" }
        return nil
    }

    private static func tidyHeadline(_ headline: String) -> String {
        var s = headline
        for prefix in ["Most likely ", "Probably ", "Could be "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: "\\s*\\([^)]*\\)", options: .regularExpression) {
            s = s.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
        }
        for prefix in ["an ", "a "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return headline }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    public static func rssiBand(rssi: Int) -> String {
        if rssi >= -45 { return "very strong" }
        if rssi >= -60 { return "strong" }
        if rssi >= -75 { return "medium" }
        if rssi >= -88 { return "weak" }
        return "very weak"
    }

    public static func uuidGloss(uuid: String) -> String? {
        if let name = VendorLookup.serviceName(for: uuid) { return name }
        guard let short = uuid16(uuid) else { return nil }
        let extra: String?
        switch short {
        case 0x1800: extra = "connection basics"
        case 0x1801: extra = "attribute protocol"
        case 0x180A: extra = "model / serial / firmware"
        case 0x180F: extra = "battery level"
        case 0x1812: extra = "keyboard, mouse, or gamepad"
        case 0x180D: extra = "heart-rate sensor"
        case 0x1810: extra = "blood-pressure sensor"
        case 0x181A: extra = "temperature / humidity style sensor"
        case 0x1844, 0x1845, 0x1846: extra = "LE cycling power/speed"
        case 0x1850, 0x184E, 0x184F: extra = "LE Audio"
        case 0xFE2C: extra = "Google Fast Pair (often buds/speakers)"
        case 0xFD5A: extra = "Samsung SmartTag"
        case 0xFD44: extra = "Apple Find My related"
        case 0xFEED, 0xFEDD: extra = "Tile tracker"
        case 0xFD50: extra = "Tuya IoT"
        case 0xFEBE, 0xFE21: extra = "Bose"
        case 0xFE78: extra = "HP printer"
        case 0xFE07: extra = "Sonos speaker"
        case 0xFEAF, 0xFEB0: extra = "Nest Weave"
        case 0xFCBF: extra = "ASSA ABLOY Opening Solutions"
        case 0xFE24: extra = "August Home lock"
        case 0xFCF4: extra = "Allegion / Schlage"
        case 0xFCB2: extra = "Apple (not ASSA ABLOY)"
        default: extra = nil
        }
        return extra
    }

    static func uuidHints(uuids: [String]) -> [ExHint] {
        var out: [ExHint] = []
        for uuid in uuids {
            guard let id = uuid16(uuid) else { continue }
            switch id {
            case 0x1812: out.append(ExHint(bucket: "hid", label: "a keyboard, mouse, or gamepad", reason: "It offers the HID (human-interface) service.", weight: 5))
            case 0x1108, 0x1112, 0x111E, 0x110B, 0x110A, 0x1131, 0x1203:
                out.append(ExHint(bucket: "audio-personal", label: "headphones, a headset, or a speaker", reason: "It offers a classic audio / headset service.", weight: 5))
            case 0x184E, 0x184F, 0x1850, 0x1851:
                out.append(ExHint(bucket: "audio-personal", label: "LE Audio earbuds or a speaker", reason: "It offers Bluetooth LE Audio services.", weight: 6))
            case 0x180D: out.append(ExHint(bucket: "health", label: "a heart-rate monitor", reason: "It offers the Heart Rate service.", weight: 6))
            case 0x1810: out.append(ExHint(bucket: "health", label: "a blood-pressure monitor", reason: "It offers the Blood Pressure service.", weight: 6))
            case 0x181A: out.append(ExHint(bucket: "sensor", label: "an environmental sensor", reason: "It offers Environmental Sensing.", weight: 4))
            case 0xFE2C: out.append(ExHint(bucket: "audio-personal", label: "earbuds or a speaker", reason: "Google Fast Pair is present (common on buds and speakers).", weight: 4))
            case 0xFD5A: out.append(ExHint(bucket: "tag", label: "a Samsung SmartTag", reason: "SmartTag service UUID.", weight: 7))
            case 0xFD44: out.append(ExHint(bucket: "tag", label: "an Apple Find My accessory", reason: "Find My related UUID.", weight: 6))
            case 0xFEED, 0xFEDD: out.append(ExHint(bucket: "tag", label: "a Tile tracker", reason: "Tile service UUID.", weight: 7))
            default: break
            }
        }
        return out
    }

    static func signatureHints(names: [String]) -> [ExHint] {
        var out: [ExHint] = []
        for raw in names {
            if isGenericSignatureName(raw) { continue }
            let n = raw.lowercased()
            if let special = specialSignatureHint(n: n, raw: raw) {
                out.append(special)
                continue
            }
            var matched = false
            for r in SigRules {
                let hit = r.contains ? n.contains(r.key) : (n == r.key)
                if hit {
                    out.append(ExHint(bucket: r.bucket, label: r.label, reason: "Matched signature \(raw).", weight: r.weight))
                    matched = true
                    break
                }
            }
            if !matched {
                out.append(ExHint(bucket: "named", label: raw, reason: "Matched signature \(raw).", weight: 7))
            }
        }
        return out
    }

    private static func specialSignatureHint(n: String, raw: String) -> ExHint? {
        func H(_ b: String, _ l: String, _ w: Int) -> ExHint {
            ExHint(bucket: b, label: l, reason: "Matched signature \(raw).", weight: w)
        }
        if n.contains("airtag") || n == "find my" || n.contains("find hub") || n.contains("dult") {
            if n.contains("dult") { return H("tag", "a DULT finder tag", 8) }
            if n.contains("find hub") { return H("tag", "a Google Find Hub tag", 8) }
            return H("tag", "an Apple AirTag / Find My tag", 8)
        }
        if n.contains("apple device") { return H("phone", "an iPhone, iPad, or Mac", 7) }
        if n.contains("apple audio") { return H("audio-personal", "AirPods, Beats, or AirPlay", 7) }
        if n.contains("microsoft") { return H("computer", "a Windows / Surface / Xbox radio", 6) }
        if n == "tesla tstpms" { return H("vehicle", "a Tesla BLE tire sensor", 7) }
        if n.contains("tpms") || n == "tirecheck" || n == "sytpms" {
            return H("vehicle", "a BLE tire-pressure sensor", 7)
        }
        if n == "vuzix" { return H("glasses", "Vuzix smart glasses", 7) }
        return nil
    }

    static func isGenericSignatureName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.caseInsensitiveCompare("Unknown Signature") == .orderedSame ||
            n.caseInsensitiveCompare("Unknown Fleet") == .orderedSame
    }

    static func wifiHints(sighting: Sighting, signatureNames: [String]) -> [ExHint] {
        let name = (sighting.name ?? "").lowercased()
        let specific = signatureNames.contains { !isGenericSignatureName($0) }
        var out: [ExHint] = []
        if name.hasPrefix("direct-") {
            out.append(specific
                ? ExHint(bucket: "wifi-direct", label: "a Wi-Fi Direct access point", reason: "SSID starts with DIRECT-.", weight: 4)
                : ExHint(bucket: "wifi-direct", label: "a phone or TV using Wi-Fi Direct", reason: "SSID starts with DIRECT-.", weight: 6))
        } else if name.hasPrefix("android-") || name.contains("hotspot") {
            if !specific {
                out.append(ExHint(bucket: "hotspot", label: "a phone hotspot", reason: "SSID looks like a phone hotspot.", weight: 6))
            }
        } else if !specific {
            out.append(ExHint(bucket: "ap", label: "a Wi-Fi access point", reason: "No matching signature for this network name.", weight: 3))
        }
        return out
    }

    public static func uuid16(_ uuid: String) -> Int? {
        let hex = uuid.filter { $0.isLetter || $0.isNumber }.uppercased()
        if hex.count == 4 { return Int(hex, radix: 16) }
        if hex.count == 32 && hex.hasPrefix("0000") && hex.hasSuffix("00001000800000805F9B34FB") {
            return Int(hex.dropFirst(4).prefix(4), radix: 16)
        }
        if hex.count == 8 { return Int(hex.suffix(4), radix: 16) }
        return nil
    }
}
