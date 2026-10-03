//
//  HuntView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
import UIKit
import CoreHaptics
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct HuntView: View {
    let sighting: Sighting
    @ObservedObject var viewModel: FieldwatchViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var pulseAnimation = false
    @State private var vibrateEnabled = true
    @State private var lastTick = Date.distantPast
    @State private var tickTimer: Timer?

    public init(sighting: Sighting, viewModel: FieldwatchViewModel) {
        self.sighting = sighting
        self.viewModel = viewModel
    }

    // Live sighting from view model
    private var liveSighting: Sighting {
        viewModel.sightings[sighting.identifier] ?? sighting
    }

    private var isMissing: Bool {
        viewModel.sightings[sighting.identifier] == nil
    }

    private var cue: HuntCue {
        Hunt.cue(samples: liveSighting.rssiSamples, now: Date(),
                 lastSeen: liveSighting.lastSeen, missing: isMissing)
    }
    
    // Proximity score 0.0 to 1.0 (clamped -100 to -30 dBm)
    private var proximity: Double {
        let rssi = Double(liveSighting.lastRssi)
        let clamped = max(-100.0, min(-35.0, rssi))
        return (clamped - (-100.0)) / 65.0
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Top Header
                HStack {
                    Button {
                        viewModel.huntTargetId = nil
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("PROXIMITY HUNT")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Spacer()
                    // Balance spacer
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .opacity(0)
                }
                .padding(.horizontal)
                
                // Target Information
                VStack(spacing: 4) {
                    Text(liveSighting.displayName)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                    Text(liveSighting.identifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Central Proximity Radar Visualizer
                ZStack {
                    // Pulsing Ring
                    Circle()
                        .stroke(huntColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 260, height: 260)
                        .scaleEffect(pulseAnimation ? 1.15 : 0.95)
                        .animation(
                            .easeInOut(duration: max(0.2, 1.2 - proximity)).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                    
                    // Main Gauge Ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                        .frame(width: 220, height: 220)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(proximity))
                        .stroke(
                            huntColor,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(-90))
                    
                    // RSSI Readout in Center
                    VStack(spacing: 4) {
                        Text("\(liveSighting.lastRssi)")
                            .font(.system(size: 56, weight: .heavy, design: .monospaced))
                            .foregroundColor(huntColor)
                        Text("dBm")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()

                // Hunt cue (trend, not meters)
                VStack(spacing: 8) {
                    Text(cue.rawValue.uppercased())
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(cue.hint)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Text("Peak \(liveSighting.maxRssi) dBm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(lastHeardText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Toggle("Titreşim", isOn: $vibrateEnabled)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 220)
                }
                .padding(.bottom, 30)
            }
            .padding()
        }
        .onAppear {
            pulseAnimation = true
            startTickLoop()
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        .onChange(of: liveSighting.lastRssi, perform: { _ in
            geigerFire()
        })
    }

    private var lastHeardText: String {
        let age = Int(Date().timeIntervalSince(liveSighting.lastSeen))
        if age < 2 { return "şimdi duyuldu" }
        return "\(age) sn önce"
    }

    private func startTickLoop() {
        tickTimer?.invalidate()
        lastTick = Date.distantPast
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            geigerFire()
        }
    }

    private func geigerFire() {
        guard let interval = Hunt.tickInterval(rssi: liveSighting.lastRssi, cue: cue) else { return }
        guard Date().timeIntervalSince(lastTick) >= interval else { return }
        lastTick = Date()
        Alerter.tick()
        if vibrateEnabled { triggerHaptic() }
    }
    
    private var huntColor: Color {
        if proximity > 0.75 { return .green }
        if proximity > 0.45 { return .yellow }
        if proximity > 0.20 { return .orange }
        return .red
    }
    
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: proximity > 0.6 ? .heavy : .light)
        generator.impactOccurred()
    }
}
