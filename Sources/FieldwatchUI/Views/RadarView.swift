//
//  RadarView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
import CoreLocation
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct RadarView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @Binding var selectedSighting: Sighting?
    
    @State private var sweepAngle: Double = 0.0
    
    public init(viewModel: FieldwatchViewModel, selectedSighting: Binding<Sighting?>) {
        self.viewModel = viewModel
        self._selectedSighting = selectedSighting
    }
    
    public var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 20
            
            ZStack {
                // Background dark military CRT style
                Color.black.ignoresSafeArea()
                
                // Concentric Range Rings
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    Circle()
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                        .frame(width: radius * 2 * fraction, height: radius * 2 * fraction)
                    
                    // RSSI range markings
                    let dbm = Int(-30 - (fraction * 65))
                    Text("\(dbm) dBm")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.green.opacity(0.4))
                        .position(x: center.x, y: center.y - (radius * fraction) + 8)
                }
                
                // Crosshairs
                Path { p in
                    p.move(to: CGPoint(x: center.x, y: center.y - radius))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    p.move(to: CGPoint(x: center.x - radius, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                }
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                
                // Rotating Sweep Line
                SweepCone(center: center, radius: radius, startAngle: sweepAngle)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.green.opacity(0.4),
                                Color.green.opacity(0.1),
                                Color.clear
                            ]),
                            center: .center,
                            startAngle: .degrees(sweepAngle - 45),
                            endAngle: .degrees(sweepAngle)
                        )
                    )
                
                // Center User Blip
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .position(center)
                
                // Active Target Blips
                ForEach(viewModel.filteredSightings) { sighting in
                    let pos = calculateBlipPosition(sighting: sighting, center: center, maxRadius: radius)
                    
                    Button {
                        selectedSighting = sighting
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(blipColor(for: sighting))
                                    .frame(width: sighting.isCoTraveling ? 14 : 10, height: sighting.isCoTraveling ? 14 : 10)
                                    .shadow(color: blipColor(for: sighting), radius: sighting.isCoTraveling ? 8 : 4)
                                
                                if sighting.isCoTraveling {
                                    Circle()
                                        .stroke(Color.red, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            
                            Text(sighting.displayName)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .background(Color.black.opacity(0.7))
                        }
                    }
                    .position(pos)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    sweepAngle = 360
                }
            }
        }
    }
    
    private func calculateBlipPosition(sighting: Sighting, center: CGPoint, maxRadius: CGFloat) -> CGPoint {
        // Distance mapped from RSSI: -30 dBm is near center (0.1), -95 dBm is outer edge (0.95)
        let clampedRssi = max(-100, min(-30, sighting.lastRssi))
        let distanceFraction = CGFloat(-30 - clampedRssi) / 70.0
        let blipDistance = max(15, distanceFraction * maxRadius)
        
        // Fixed synthetic angle per identifier so targets stay stationary unless moved
        let hash = abs(sighting.identifier.hashValue)
        let angleDegrees = Double(hash % 360)
        let radians = angleDegrees * .pi / 180.0
        
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * blipDistance,
            y: center.y + CGFloat(sin(radians)) * blipDistance
        )
    }
    
    private func blipColor(for sighting: Sighting) -> Color {
        if sighting.isCoTraveling {
            return .red
        }
        if sighting.kind == .wifi {
            return .cyan
        }
        if sighting.fleetName != nil {
            return .yellow
        }
        return .green
    }
}

struct SweepCone: Shape {
    var startAngle: Double
    var center: CGPoint
    var radius: CGFloat

    init(center: CGPoint, radius: CGFloat, startAngle: Double) {
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
    }

    var animatableData: Double {
        get { startAngle }
        set { startAngle = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: center)
        p.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle - 45),
            endAngle: .degrees(startAngle),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}
