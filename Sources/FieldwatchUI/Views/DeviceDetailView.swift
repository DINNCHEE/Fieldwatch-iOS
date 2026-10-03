//
//  DeviceDetailView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct DeviceDetailView: View {
    let sighting: Sighting
    @ObservedObject var viewModel: FieldwatchViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingHuntView = false
    
    public init(sighting: Sighting, viewModel: FieldwatchViewModel) {
        self.sighting = sighting
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            List {
                // Header Card
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(sighting.displayName)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                            Spacer()
                            Text(sighting.kind.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(sighting.kind == .wifi ? Color.cyan.opacity(0.2) : Color.blue.opacity(0.2))
                                .foregroundColor(sighting.kind == .wifi ? .cyan : .blue)
                                .cornerRadius(6)
                        }
                        
                        Text(sighting.identifier)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let vendor = sighting.vendor, !vendor.isEmpty {
                            Text(vendor)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        
                        if sighting.isCoTraveling {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("MOVING WITH YOU - POTENTIAL TAIL")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Identity guess (what the radio is advertising)
                Section("What This Looks Like") {
                    let guessNames: [String] = sighting.fleetName.map { [$0] } ?? []
                    let guess = DeviceExplain.guess(sighting: sighting, signatureNames: guessNames)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guess.headline)
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                        Text(guess.because)
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                        Text("Confidence: \(guess.confidence.rawValue)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Hunt & Locate action
                Section {
                    Button {
                        viewModel.huntTargetId = sighting.identifier
                        showingHuntView = true
                    } label: {
                        HStack {
                            Image(systemName: "scope")
                                .font(.title3)
                            Text("Launch Proximity Hunt Mode")
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(.green)
                    }
                }
                
                // Role Hints
                if !sighting.roleHints.isEmpty {
                    Section("Role & Intelligence Hints") {
                        ForEach(sighting.roleHints, id: \.self) { hint in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.label)
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                                Text(hint.reason)
                                    .font(.system(.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Decoded RF Payload
                if !sighting.decodedFields.isEmpty {
                    Section("Decoded Payload Fields") {
                        ForEach(sighting.decodedFields, id: \.self) { field in
                            HStack {
                                Text(field.label)
                                    .font(.system(.caption))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(field.value)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                
                // Signal & Timing
                Section("RF Observations & Metrics") {
                    HStack {
                        Text("Current RSSI")
                        Spacer()
                        Text("\(sighting.lastRssi) dBm")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    HStack {
                        Text("Peak RSSI")
                        Spacer()
                        Text("\(sighting.maxRssi) dBm")
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("Observed Packets")
                        Spacer()
                        Text("\(sighting.count)")
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("First Seen")
                        Spacer()
                        Text(sighting.firstSeen.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospaced())
                    }
                    HStack {
                        Text("Last Seen")
                        Spacer()
                        Text(sighting.lastSeen.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospaced())
                    }
                }
                
                // Raw Manufacturer Records
                if !sighting.facts.mfgRecords.isEmpty {
                    Section("Raw Manufacturer Records") {
                        ForEach(sighting.facts.mfgRecords, id: \.self) { mfg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Company ID: 0x\(String(format: "%04X", mfg.companyId))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(mfg.dataHex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Location Information
                if let loc = sighting.location {
                    Section("GPS Observation") {
                        HStack {
                            Text("Coordinates")
                            Spacer()
                            Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                .font(.caption.monospaced())
                        }
                        HStack {
                            Text("Tracked GPS Fixes")
                            Spacer()
                            Text("\(sighting.locationHistory.count)")
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingHuntView) {
                HuntView(sighting: sighting, viewModel: viewModel)
            }
        }
    }
}
