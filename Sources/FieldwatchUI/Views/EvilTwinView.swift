//
//  EvilTwinView.swift
//  Fieldwatch
//
//  Connected-network audit: known-BSSID memory, gateway change,
//  DNS hijack test. Defensive only.
//

import SwiftUI
import NetworkExtension
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

private struct KnownNetsStore {
    static let bssidsKey = "fw_known_bssids" // [ssid: [bssid]]
    static let gwKey = "fw_known_gw" // [ssid: gateway]

    static func loadBssids() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: bssidsKey) as? [String: [String]] ?? [:]
    }

    static func loadGw() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: gwKey) as? [String: String] ?? [:]
    }

    static func learn(ssid: String, bssid: String, gateway: String?) {
        var b = loadBssids()
        var list = b[ssid] ?? []
        if !list.contains(bssid) { list.append(bssid) }
        b[ssid] = Array(list.suffix(8))
        UserDefaults.standard.set(b, forKey: bssidsKey)
        if let gateway = gateway {
            var g = loadGw()
            g[ssid] = gateway
            UserDefaults.standard.set(g, forKey: gwKey)
        }
    }
}

public struct EvilTwinView: View {
    @State private var ssid: String = ""
    @State private var bssid: String = ""
    @State private var gateway: String = ""
    @State private var verdicts: [String] = []
    @State private var dnsText: String = ""
    @State private var checking = false

    public init() {}

    public var body: some View {
        List {
            Section("Bağlı Ağ") {
                HStack { Text("SSID"); Spacer(); Text(ssid.isEmpty ? "-" : ssid).font(.caption.monospaced()) }
                HStack { Text("BSSID"); Spacer(); Text(bssid.isEmpty ? "-" : bssid).font(.caption.monospaced()) }
                HStack { Text("Ağ geçidi"); Spacer(); Text(gateway.isEmpty ? "-" : gateway).font(.caption.monospaced()) }
                Button("Ağı Öğren (güvenilir işaretle)") {
                    if !ssid.isEmpty, !bssid.isEmpty {
                        KnownNetsStore.learn(ssid: ssid, bssid: bssid, gateway: gateway.isEmpty ? nil : gateway)
                        runChecks()
                    }
                }
            }

            Section("Değerlendirme") {
                if verdicts.isEmpty {
                    Text("Henüz değerlendirme yok.")
                        .foregroundColor(.secondary)
                }
                ForEach(verdicts, id: \.self) { v in
                    Text(v).font(.caption)
                }
            }

            Section("DNS Kaçırma Testi") {
                Button(checking ? "Test ediliyor…" : "Testi Başlat") {
                    checking = true
                    dnsText = ""
                    Task {
                        let result = await DnsAudit.audit()
                        await MainActor.run {
                            dnsText = "\(result.verdict)\nSistem: \(result.systemIPs.joined(separator: ", "))\nDoH: \(result.dohIPs.joined(separator: ", "))"
                            checking = false
                        }
                    }
                }
                .disabled(checking)
                if !dnsText.isEmpty {
                    Text(dnsText).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Ağ Denetimi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                ssid = network?.ssid ?? ""
                bssid = network?.bssid ?? ""
                gateway = LanDiscovery.shared.lastGateway ?? ""
                runChecks()
            }
        }
    }

    private func runChecks() {
        var out: [String] = []
        if ssid.isEmpty {
            out.append("WiFi'ya bağlı değilsin.")
            verdicts = out
            return
        }
        let known = KnownNetsStore.loadBssids()[ssid] ?? []
        if known.isEmpty {
            out.append("ℹ Bu ağ ilk kez görülüyor — güvenilirse 'Ağı Öğren'e bas.")
        } else if !known.contains(bssid) {
            out.append("⚠ Bu SSID'de yeni BSSID (\(bssid)). Sahte ikiz olabilir; DNS testini çalıştır.")
        } else {
            out.append("✓ BSSID bilinen listede.")
        }
        if let gw = LanDiscovery.shared.lastGateway {
            let knownGw = KnownNetsStore.loadGw()[ssid]
            if let knownGw = knownGw, knownGw != gw {
                out.append("⚠ Ağ geçidi değişmiş (\(knownGw) → \(gw)).")
            } else if knownGw == nil {
                out.append("ℹ Ağ geçidi kaydedildi: \(gw).")
            } else {
                out.append("✓ Ağ geçidi aynı.")
            }
        }
        if RadioDb.shared.isRandomized(bssid) {
            out.append("ℹ BSSID lokal yönetimli (sanal/misafir ağ olabilir).")
        }
        verdicts = out
    }
}
