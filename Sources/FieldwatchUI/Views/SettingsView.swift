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
                    
                    HStack {
                        Text("Wi-Fi Scanner Mode")
                        Spacer()
                        Text(viewModel.wifiScanMode.rawValue)
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
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Port)")
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
                "name": s.name ?? "",
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
