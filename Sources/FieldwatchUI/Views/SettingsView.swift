//
//  SettingsView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct SettingsView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    
    @State private var takHost: String = TakPublisher.shared.targetHost
    @State private var takPort: String = String(TakPublisher.shared.targetPort)
    @State private var takEnabled: Bool = TakPublisher.shared.isEnabled
    @State private var wifiMode: WifiScanner.ScanMode = WifiScanner.shared.activeMode
    @State private var companionPort: String = String(WifiScanner.shared.companionPort)
    @State private var wigleName: String = ""
    @State private var wigleToken: String = ""
    @State private var wigleSaved: Bool = WigleLookup.hasCredentials
    @State private var catalogStatus: String = ""
    @State private var showingExportSheet = false
    @State private var exportText = ""
    
    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            Form {
                // Radio Controls
                Section("Radio Engine Configuration") {
                    Picker("Scan Intensity", selection: $viewModel.scanIntensity) {
                        ForEach(ScanIntensity.allCases, id: \.self) { intensity in
                            Text(intensity.label).tag(intensity)
                        }
                    }
                    .onChange(of: viewModel.scanIntensity, perform: { val in
                        if viewModel.isBleScanning {
                            viewModel.startAllScans()
                        }
                    })
                    
                    Picker("Wi-Fi Scanner Mode", selection: $wifiMode) {
                        Text("Connected AP Only").tag(WifiScanner.ScanMode.publicConnectedOnly)
                        Text("MobileWiFi (TrollStore)").tag(WifiScanner.ScanMode.privateMobileWiFi)
                        Text("Companion (ESP32)").tag(WifiScanner.ScanMode.companionHardware)
                    }
                    .onChange(of: wifiMode, perform: { mode in
                        let port = UInt16(companionPort) ?? 8888
                        WifiScanner.shared.setMode(mode, companionPort: port)
                        viewModel.wifiScanMode = mode
                    })

                    if wifiMode == .publicConnectedOnly {
                        Text("Stock iOS pasif Wi-Fi taramasına izin vermez. Bu mod bağlı AP + LAN keşfi (Bonjour/UPnP cihazlar + yerel ağ taraması) yapar. Tüm kablosuz ağlar için TrollStore (MobileWiFi) veya ESP32 Companion gerekir.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if wifiMode == .companionHardware {
                        HStack {
                            Text("Companion UDP Port")
                            Spacer()
                            TextField("Port", text: $companionPort)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    let port = UInt16(companionPort) ?? 8888
                                    WifiScanner.shared.setMode(.companionHardware, companionPort: port)
                                }
                        }
                        Text("ESP32 köprüsü bu porta JSON göndermeli: {\"bssid\":\"AA:BB:CC:DD:EE:FF\",\"ssid\":\"Ad\",\"rssi\":-70}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Watchlist alerts
                Section("Uyarılar (Watchlist)") {
                    Toggle("Bip sesi", isOn: Binding(
                        get: { Alerter.beepEnabled },
                        set: { Alerter.setBeep($0) }
                    ))
                    Toggle("Sesli uyarı", isOn: Binding(
                        get: { Alerter.voiceEnabled },
                        set: { Alerter.setVoice($0) }
                    ))
                    Toggle("Bildirim", isOn: Binding(
                        get: { Alerter.notifyEnabled },
                        set: {
                            Alerter.setNotify($0)
                            if $0 { Alerter.requestNotificationPermission() }
                        }
                    ))
                    Button("Test Uyarısı") {
                        Alerter.requestNotificationPermission()
                        Alerter.test()
                    }
                    Text("Takip alarmı + işaretli cihazlar için. Cihaz detayından yıldızla işaretle ve alarmı aç.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Wigle lookup (BYOK)
                Section("Wigle Arama (BSSID)") {
                    HStack {
                        Text("API Name")
                        Spacer()
                        TextField("wigle.net/account", text: $wigleName)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    HStack {
                        Text("API Token")
                        Spacer()
                        SecureField("Token", text: $wigleToken)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Button("Kaydet") {
                            if WigleLookup.saveCredentials(
                                name: wigleName.trimmingCharacters(in: .whitespaces),
                                token: wigleToken.trimmingCharacters(in: .whitespaces)) {
                                wigleSaved = true
                                wigleToken = ""
                            }
                        }
                        Spacer()
                        Button("Temizle", role: .destructive) {
                            WigleLookup.clearCredentials()
                            wigleName = ""
                            wigleToken = ""
                            wigleSaved = false
                        }
                    }
                    Text(wigleSaved ? "Anahtar kayıtlı ✓" : "Kayıtlı anahtar yok.")
                        .font(.caption)
                        .foregroundColor(wigleSaved ? .green : .secondary)
                    Text("Ücretsiz hesap: wigle.net → Account. Anahtar cihazdaki kilitli kasada durur, kimseyle paylaşılmaz. Veriler © WiGLE.net, tekil sorgu.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    if let saved = Keychain.load(account: WigleLookup.nameAccount) {
                        wigleName = saved
                    }
                }

                // Signature catalog update
                Section("İmza Kataloğu") {
                    HStack {
                        Text("Sürüm")
                        Spacer()
                        Text("v\(SignatureEngine.shared.catalogVersion)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Button("GitHub'dan Güncelle") {
                        catalogStatus = "İndiriliyor…"
                        Task {
                            let msg = await CatalogUpdate.checkAndApply()
                            await MainActor.run { catalogStatus = msg }
                        }
                    }
                    if !catalogStatus.isEmpty {
                        Text(catalogStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // TAK / Cursor on Target Integration
                Section("ATAK / iTAK Integration (Cursor on Target)") {
                    Toggle("Enable CoT Broadcast", isOn: $takEnabled)
                        .onChange(of: takEnabled, perform: { val in
                            saveTakSettings()
                        })
                    
                    HStack {
                        Text("Target Host")
                        Spacer()
                        TextField("IP or Multicast", text: $takHost)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onSubmit { saveTakSettings() }
                    }
                    
                    HStack {
                        Text("Target Port")
                        Spacer()
                        TextField("Port", text: $takPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onSubmit { saveTakSettings() }
                    }
                }
                
                // Tools hub
                Section("Araçlar") {
                    NavigationLink("Ağ Denetimi (evil-twin + DNS)") { EvilTwinView() }
                    NavigationLink("Hava Sahası (uçaklar)") { AirspaceView(viewModel: viewModel) }
                    NavigationLink("Pusula (sinyale yön)") { CompassView(viewModel: viewModel) }
                    NavigationLink("Kanal Doluluk") { ChannelChartView(viewModel: viewModel) }
                    NavigationLink("Otel Modu") { HotelModeView(viewModel: viewModel) }
                    NavigationLink("Ultrasonik Tarama") { UltrasonicView() }
                    NavigationLink("OBD Okuma (kendi aracın)") { ObdView() }
                    NavigationLink("Güvenlik Rehberleri") { GuidesView() }
                }

                // Data & Export
                Section("Data Management") {
                    HStack {
                        Text("Tracked Signals")
                        Spacer()
                        Text("\(viewModel.sightings.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total Packets Captured")
                        Spacer()
                        Text("\(viewModel.totalObservationsCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Export SITREP (JSON)") {
                        generateExport()
                        showingExportSheet = true
                    }
                    
                    Button(role: .destructive) {
                        viewModel.clearAllSightings()
                    } label: {
                        Text("Clear All Captured Signals")
                    }
                }
                
                // About
                Section("About Fieldwatch iOS") {
                    HStack {
                        Text("Radio Database")
                        Spacer()
                        Text(RadioDb.shared.isReady ? "\(RadioDb.shared.nameCount) names" : "Not loaded")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Yeniden başlatma")
                        Spacer()
                        Text(viewModel.rebootCount > 0 ? "\(viewModel.rebootCount)x" : "yok")
                            .foregroundColor(viewModel.rebootCount > 0 ? .orange : .secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.8 (Port)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Original Author")
                        Spacer()
                        Text("OffGridPete (Android)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("License")
                        Spacer()
                        Text("MIT License")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingExportSheet) {
                NavigationView {
                    ScrollView {
                        Text(exportText)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("SITREP Export")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingExportSheet = false }
                        }
                    }
                }
            }
        }
    }
    
    private func saveTakSettings() {
        let port = UInt16(takPort) ?? 6969
        TakPublisher.shared.configure(host: takHost, port: port, enabled: takEnabled)
    }
    
    private func generateExport() {
        let items = viewModel.sightings.values.map { s in
            [
                "id": s.identifier,
                "radio": s.kind.rawValue,
                "name": s.displayName,
                "fleet": s.fleetName ?? "",
                "rssi": s.lastRssi,
                "coTraveling": s.isCoTraveling,
                "lastSeen": s.lastSeen.ISO8601Format()
            ] as [String : Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: items, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            exportText = str
        }
    }
}
