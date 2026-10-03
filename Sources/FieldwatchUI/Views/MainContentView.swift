//
//  MainContentView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct MainContentView: View {
    @StateObject private var viewModel = FieldwatchViewModel()
    @State private var selectedSighting: Sighting? = nil
    @State private var showingFilterSheet = false
    
    public init() {}
    
    public var body: some View {
        TabView {
            // Main Scanner Tab (Radar + List)
            NavigationView {
                VStack(spacing: 0) {
                    // Tactical Status Header
                    headerBar
                    
                    // Alert Banner for Co-Traveling Trackers ("Moving with you")
                    if viewModel.coTravelingCount > 0 {
                        coTravelBanner
                    }
                    
                    // Content Mode (Radar vs List)
                    if viewModel.viewMode == .radar {
                        RadarView(viewModel: viewModel, selectedSighting: $selectedSighting)
                    } else {
                        LiveListView(viewModel: viewModel, selectedSighting: $selectedSighting)
                    }
                }
                .navigationTitle("Fieldwatch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Picker("Mode", selection: $viewModel.viewMode) {
                            Image(systemName: "circle.grid.cross").tag(ViewMode.radar)
                            Image(systemName: "list.bullet").tag(ViewMode.list)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 12) {
                            Button {
                                showingFilterSheet = true
                            } label: {
                                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundColor(hasActiveFilters ? .green : .primary)
                            }
                            
                            Button {
                                if viewModel.isBleScanning {
                                    viewModel.stopAllScans()
                                } else {
                                    viewModel.startAllScans()
                                }
                            } label: {
                                Image(systemName: viewModel.isBleScanning ? "stop.circle.fill" : "play.circle.fill")
                                    .foregroundColor(viewModel.isBleScanning ? .red : .green)
                            }
                        }
                    }
                }
            }
            .tabItem {
                Label("Scanner", systemImage: "antenna.radiowaves.left.and.right")
            }
            
            // Categories Tab
            CategoryView(viewModel: viewModel, selectedSighting: $selectedSighting)
                .tabItem {
                    Label("Sınıflar", systemImage: "square.grid.2x2")
                }

            // Cameras Tab
            CameraView(viewModel: viewModel)
                .tabItem {
                    Label("Kameralar", systemImage: "video.fill")
                }

            // Sweep Tab
            SweepView(viewModel: viewModel)
                .tabItem {
                    Label("Süpürme", systemImage: "magnifyingglass")
                }

            // Reports Tab
            ReportsView(viewModel: viewModel)
                .tabItem {
                    Label("Raporlar", systemImage: "doc.text")
                }

            // Fleets Tab
            FleetsView()
                .tabItem {
                    Label("Fleets", systemImage: "shield.lefthalf.filled")
                }
            
            // Settings Tab
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedSighting) { sighting in
            DeviceDetailView(sighting: sighting, viewModel: viewModel)
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheetView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.startAllScans()
        }
    }
    
    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isBleScanning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.isBleScanning ? "SWEEPING" : "STANDBY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(viewModel.isBleScanning ? .green : .red)
            }
            
            Spacer()
            
            Text("TARGETS: \(viewModel.filteredSightings.count) / \(viewModel.sightings.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let loc = viewModel.currentLocation {
                Text(String(format: "GPS: %.4f, %.4f", loc.latitude, loc.longitude))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("GPS: ACQUIRING")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }
    
    private var coTravelBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.black)
            Text("ALERT: \(viewModel.coTravelingCount) DEVICE(S) MOVING WITH YOU")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.black)
            Spacer()
            Button {
                viewModel.filterOnlyCoTraveling.toggle()
            } label: {
                Text(viewModel.filterOnlyCoTraveling ? "SHOW ALL" : "ISOLATE")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red)
    }
    
    private var hasActiveFilters: Bool {
        viewModel.selectedRadioFilter != nil ||
        viewModel.minRssiThreshold > -100 ||
        viewModel.filterOnlyCoTraveling ||
        viewModel.filterOnlyIdentified ||
        viewModel.filterOnlyBookmarked ||
        viewModel.hideFastPairAccountKey ||
        !viewModel.searchQuery.isEmpty
    }
}

// Filter sheet
struct FilterSheetView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Search") {
                    TextField("Filter by Name, MAC, Fleet...", text: $viewModel.searchQuery)
                }
                
                Section("Radio Frequency") {
                    Picker("Radio Kind", selection: $viewModel.selectedRadioFilter) {
                        Text("All Radios").tag(Optional<RadioKind>.none)
                        Text("Bluetooth LE Only").tag(Optional<RadioKind>.some(.ble))
                        Text("Wi-Fi Only").tag(Optional<RadioKind>.some(.wifi))
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Signal Strength Threshold") {
                    HStack {
                        Text("Minimum RSSI")
                        Spacer()
                        Text("\(viewModel.minRssiThreshold) dBm")
                            .monospaced()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.minRssiThreshold) },
                            set: { viewModel.minRssiThreshold = Int($0) }
                        ),
                        in: -100...(-40),
                        step: 5
                    )
                }
                
                Section("Intelligence Filters") {
                    Toggle("Only Co-Traveling / Stalkers", isOn: $viewModel.filterOnlyCoTraveling)
                    Toggle("Only Identified Fleets", isOn: $viewModel.filterOnlyIdentified)
                    Toggle("Only Bookmarked", isOn: $viewModel.filterOnlyBookmarked)
                    Toggle("Hide Fast Pair account-key", isOn: $viewModel.hideFastPairAccountKey)
                }

                Section("Presets") {
                    HStack {
                        presetButton("Tümü") {
                            resetFilters(on: viewModel)
                        }
                        presetButton("Wi-Fi") {
                            resetFilters(on: viewModel)
                            viewModel.selectedRadioFilter = .wifi
                        }
                        presetButton("BLE") {
                            resetFilters(on: viewModel)
                            viewModel.selectedRadioFilter = .ble
                        }
                    }
                    HStack {
                        presetButton("Güçlü") {
                            resetFilters(on: viewModel)
                            viewModel.minRssiThreshold = -70
                        }
                        presetButton("Hareketli") {
                            resetFilters(on: viewModel)
                            viewModel.filterOnlyCoTraveling = true
                        }
                        presetButton("İzlenen") {
                            resetFilters(on: viewModel)
                            viewModel.filterOnlyBookmarked = true
                        }
                    }
                    Text("İzlenen: detaydan yıldızladıkların.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("Reset Filters") {
                        resetFilters(on: viewModel)
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15))
            .cornerRadius(8)
    }

    private func resetFilters(on viewModel: FieldwatchViewModel) {
        viewModel.searchQuery = ""
        viewModel.selectedRadioFilter = nil
        viewModel.minRssiThreshold = -100
        viewModel.filterOnlyCoTraveling = false
        viewModel.filterOnlyIdentified = false
        viewModel.filterOnlyBookmarked = false
        viewModel.hideFastPairAccountKey = false
    }
}
