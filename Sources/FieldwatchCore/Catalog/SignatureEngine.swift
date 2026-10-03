//
//  SignatureEngine.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation

public final class SignatureEngine: @unchecked Sendable {
    public static let shared = SignatureEngine()
    
    private var catalog: FleetCatalog?
    private var fleets: [Fleet] = []
    private let lock = NSLock()
    
    public init() {
        RadioDb.shared.load()
        loadDefaultCatalog()
    }
    
    public func loadCatalog(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let parsed = try decoder.decode(FleetCatalog.self, from: data)
            lock.lock()
            self.catalog = parsed
            self.fleets = parsed.fleets
            lock.unlock()
            return true
        } catch {
            print("Failed to load catalog from \(url): \(error)")
            return false
        }
    }
    
    public func loadDefaultCatalog() {
        #if SWIFT_PACKAGE
        if let bundleUrl = Bundle.module.url(forResource: "fieldwatch-signatures-v2", withExtension: "json") {
            _ = loadCatalog(from: bundleUrl)
            return
        }
        #endif
        if let bundleUrl = Bundle.main.url(forResource: "fieldwatch-signatures-v2", withExtension: "json") {
            _ = loadCatalog(from: bundleUrl)
            return
        }
        // Fallback or bundled resource directory
        let searchPaths = [
            "Resources/fieldwatch-signatures-v2.json",
            "../Resources/fieldwatch-signatures-v2.json"
        ]
        for path in searchPaths {
            let fileUrl = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                if loadCatalog(from: fileUrl) { return }
            }
        }
    }
    
    public var activeFleets: [Fleet] {
        lock.lock()
        defer { lock.unlock() }
        return fleets
    }
    
    public func toggleFleet(id: String, enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = fleets.firstIndex(where: { $0.id == id }) {
            fleets[idx].enabled = enabled
        }
    }
    
    // MARK: - Matching Logic
    public func match(
        name: String?,
        macOrId: String,
        kind: RadioKind,
        facts: RadioFacts
    ) -> (fleetId: String, fleetName: String, colorIndex: Int)? {
        lock.lock()
        let localFleets = fleets
        lock.unlock()
        
        for fleet in localFleets where fleet.enabled {
            var matchedRuleCount = 0
            let activeRules = fleet.rules.filter { $0.enabled }
            guard !activeRules.isEmpty else { continue }
            
            for rule in activeRules {
                if matches(rule: rule, name: name, macOrId: macOrId, kind: kind, facts: facts) {
                    matchedRuleCount += 1
                    if fleet.matchAny {
                        return (fleet.id, fleet.name, fleet.colorIndex)
                    }
                }
            }
            
            if !fleet.matchAny && matchedRuleCount == activeRules.count {
                return (fleet.id, fleet.name, fleet.colorIndex)
            }
        }
        return nil
    }
    
    private func matches(
        rule: Rule,
        name: String?,
        macOrId: String,
        kind: RadioKind,
        facts: RadioFacts
    ) -> Bool {
        // Filter by radio kind if specified
        if let radio = rule.radio, radio != "ANY" {
            if radio == "WIFI" && kind != .wifi { return false }
            if radio == "BLE" && kind != .ble { return false }
        }
        
        switch rule.kind {
        case "NAME_GLOB":
            guard let pattern = rule.text?.lowercased(), let target = name?.lowercased() else { return false }
            return matchesGlob(pattern: pattern, text: target)
            
        case "OUI":
            guard let prefix = rule.text?.replacingOccurrences(of: ":", with: "").uppercased() else { return false }
            let cleanMac = macOrId.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
            return cleanMac.hasPrefix(prefix)
            
        case "MFG":
            guard let companyId = rule.companyId else { return false }
            let prefixHex = (rule.dataPrefixHex ?? "").uppercased()
            for mfg in facts.mfgRecords where mfg.companyId == companyId {
                if prefixHex.isEmpty || mfg.dataHex.uppercased().hasPrefix(prefixHex) {
                    return true
                }
            }
            return false
            
        case "SERVICE_DATA":
            guard let uuid = rule.text?.uppercased() else { return false }
            let prefixHex = (rule.dataPrefixHex ?? "").uppercased()
            for sdata in facts.serviceDataRecords where sdata.uuid.uppercased().contains(uuid) {
                if prefixHex.isEmpty || sdata.dataHex.uppercased().hasPrefix(prefixHex) {
                    return true
                }
            }
            return false
            
        case "UUID":
            guard let target = rule.text?.uppercased() else { return false }
            return facts.serviceUuids.contains(where: { $0.uppercased().contains(target) })
            
        default:
            return false
        }
    }
    
    private func matchesGlob(pattern: String, text: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") && pattern.hasPrefix("*") {
            let sub = pattern.dropFirst().dropLast()
            return text.contains(sub)
        }
        if pattern.hasSuffix("*") {
            return text.hasPrefix(pattern.dropLast())
        }
        if pattern.hasPrefix("*") {
            return text.hasSuffix(pattern.dropFirst())
        }
        return pattern == text
    }
}
