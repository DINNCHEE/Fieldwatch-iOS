//
//  CompassView.swift
//  Fieldwatch
//
//  Bearing compass to the strongest GPS-tagged sighting.
//  Guidance cone, not precision DF (phone has no AoA hardware).
//

import SwiftUI
import CoreLocation
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

private final class HeadingProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var heading: Double = 0
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 3
        manager.startUpdatingHeading()
    }

    deinit { manager.stopUpdatingHeading() }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
}

public struct CompassView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @StateObject private var compass = HeadingProvider()

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private var target: Sighting? {
        viewModel.filteredSightings
            .filter { $0.location != nil }
            .sorted { $0.lastRssi > $1.lastRssi }
            .first
    }

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brg = atan2(y, x) * 180 / .pi
        if brg < 0 { brg += 360 }
        return brg
    }

    public var body: some View {
        VStack(spacing: 16) {
            if let me = viewModel.currentLocation, let t = target, let dest = t.location {
                let brg = bearing(from: me, to: dest)
                let relative = brg - compass.heading
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 220, height: 220)
                    Text("N")
                        .font(.headline)
                        .offset(y: -100)
                        .rotationEffect(.degrees(-compass.heading))
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)
                        .rotationEffect(.degrees(relative))
                }
                Text(t.displayName)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .lineLimit(1)
                Text("Yön \(Int(brg))° · \(t.lastRssi) dBm")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("Yaklaşık yöndür (pusula ±10°, GPS ±10m). Hassas kerteriz değildir.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("GPS konumlu hedef yok. Dışarıda tara, sinyalin kaydedildiği nokta hedef olur.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Pusula")
        .navigationBarTitleDisplayMode(.inline)
    }
}
