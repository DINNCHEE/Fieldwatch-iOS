//
//  LiveListView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct LiveListView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @Binding var selectedSighting: Sighting?
    
    public init(viewModel: FieldwatchViewModel, selectedSighting: Binding<Sighting?>) {
        self.viewModel = viewModel
        self._selectedSighting = selectedSighting
    }
    
    public var body: some View {
        List {
            ForEach(viewModel.filteredSightings) { sighting in
                Button {
                    selectedSighting = sighting
                } label: {
                    HStack(spacing: 12) {
                        // Radio icon
                        ZStack {
                            Circle()
                                .fill(sighting.kind == .wifi ? Color.cyan.opacity(0.15) : Color.blue.opacity(0.15))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: sighting.kind == .wifi ? "wifi" : "dot.radiowaves.left.and.right")
                                .foregroundColor(sighting.kind == .wifi ? .cyan : .blue)
                                .font(.system(size: 18))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sighting.displayName)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(sighting.lastRssi) dBm")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundColor(rssiColor(sighting.lastRssi))
                            }
                            
                            HStack(spacing: 6) {
                                Text(sighting.identifier)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                // RSSI Sparkline
                                SparklineView(values: sighting.rssiHistory)
                                    .frame(width: 50, height: 14)
                            }
                            
                            // Badges row
                            HStack(spacing: 6) {
                                if Date().timeIntervalSince(sighting.firstSeen) < 60 {
                                    Text("YENİ")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }

                                if let weakest = sighting.rssiHistory.min(),
                                   sighting.lastRssi - weakest > 12 {
                                    Text("▲ yaklaşıyor")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }

                                if sighting.isCoTraveling {
                                    Label("MOVING WITH YOU", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.2))
                                        .foregroundColor(.red)
                                        .cornerRadius(4)
                                }
                                
                                if let vendor = sighting.vendor, vendor != sighting.displayName {
                                    Text(vendor)
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }

                                if let fleet = sighting.fleetName {
                                    Text(fleet)
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.2))
                                        .foregroundColor(.yellow)
                                        .cornerRadius(4)
                                }
                                
                                if let hint = sighting.roleHints.first {
                                    Text(hint.label)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 { return .green }
        if rssi > -75 { return .yellow }
        if rssi > -85 { return .orange }
        return .red
    }
}

public struct SparklineView: View {
    let values: [Int]
    
    public var body: some View {
        GeometryReader { geo in
            if values.count <= 1 {
                Color.clear
            } else {
                let minVal = CGFloat(values.min() ?? -100)
                let maxVal = CGFloat(values.max() ?? -40)
                let range = max(1.0, maxVal - minVal)

                Path { path in
                    let stepX = geo.size.width / CGFloat(values.count - 1)
                    for (idx, val) in values.enumerated() {
                        let x = CGFloat(idx) * stepX
                        let y = geo.size.height - ((CGFloat(val) - minVal) / range * geo.size.height)
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.green, lineWidth: 1.5)
            }
        }
    }
}
