//
//  AirspaceView.swift
//  Fieldwatch
//
//  Nearby ADS-B aircraft (OpenSky, anonymous quota) next to drone sightings.
//

import SwiftUI
import CoreLocation
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct Aircraft: Identifiable, Sendable {
    public var id: String
    public var callsign: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var onGround: Bool
}

public struct AirspaceView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @State private var aircraft: [Aircraft] = []
    @State private var status: String = ""
    @State private var loading = false

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private struct OpenSky: Decodable {
        var states: [[OpenSkyValue]]?
        struct OpenSkyValue: Decodable {
            var s: String?
            var d: Double?
            var b: Bool?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let v = try? c.decode(String.self) { s = v }
                else if let v = try? c.decode(Double.self) { d = v }
                else if let v = try? c.decode(Bool.self) { b = v }
            }
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let loc = viewModel.currentLocation {
                SharedMap(
                    trail: [],
                    points: aircraft.map {
                        MapPoint(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                                 title: $0.callsign)
                    } + [MapPoint(id: "me", coordinate: loc, title: "Sen")]
                )
                .cornerRadius(12)
                .padding(.horizontal)
                .frame(height: 300)
            } else {
                Text("Konum bekleniyor…")
                    .foregroundColor(.secondary)
                    .padding()
            }

            HStack {
                Button(loading ? "Yükleniyor…" : "Uçakları Getir") { fetch() }
                    .fontWeight(.bold)
                    .disabled(loading)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            List {
                Section("Yakındaki uçaklar (\(aircraft.count))") {
                    ForEach(aircraft.prefix(30)) { a in
                        HStack {
                            Text(a.callsign.isEmpty ? a.id : a.callsign)
                                .font(.system(.subheadline, design: .monospaced))
                            Spacer()
                            if let alt = a.altitude {
                                Text("\(Int(alt)) m\(a.onGround ? " (yerde)" : "")")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Kaynak: OpenSky Network (anonim kota ~400/gün). Drone'lar RemoteID ile uygulamada görünür; uçaklar ADS-B'dir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Hava Sahası")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fetch() {
        guard let loc = viewModel.currentLocation else {
            status = "Konum yok."
            return
        }
        loading = true
        status = ""
        let d = 0.25
        let urlString = "https://opensky-network.org/api/states/all?lamin=\(loc.latitude - d)&lomin=\(loc.longitude - d)&lamax=\(loc.latitude + d)&lomax=\(loc.longitude + d)"
        guard let url = URL(string: urlString) else {
            loading = false
            return
        }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(OpenSky.self, from: data),
                      let states = decoded.states else {
                    await MainActor.run {
                        status = "Yanıt alınamadı (kota dolmuş olabilir)."
                        loading = false
                    }
                    return
                }
                let list: [Aircraft] = states.compactMap { row in
                    guard row.count > 9,
                          let icao = row[0].s,
                          let lon = row[5].d,
                          let lat = row[6].d else { return nil }
                    let call = (row[1].s ?? "").trimmingCharacters(in: .whitespaces)
                    return Aircraft(id: icao, callsign: call, latitude: lat, longitude: lon,
                                    altitude: row[7].d, onGround: row[8].b ?? false)
                }
                await MainActor.run {
                    aircraft = list
                    status = "\(list.count) uçak"
                    loading = false
                }
            } catch {
                await MainActor.run {
                    status = "Ağ hatası."
                    loading = false
                }
            }
        }
    }
}
