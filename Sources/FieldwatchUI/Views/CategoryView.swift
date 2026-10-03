//
//  CategoryView.swift
//  Fieldwatch
//
//  Devices grouped under human categories (audio, PC, tags…).
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct CategoryView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @Binding var selectedSighting: Sighting?

    public init(viewModel: FieldwatchViewModel, selectedSighting: Binding<Sighting?>) {
        self.viewModel = viewModel
        self._selectedSighting = selectedSighting
    }

    private static func categoryKey(_ s: Sighting) -> String {
        if let hint = s.roleHints.first?.bucket, !hint.isEmpty { return hint }
        if s.fleetName != nil { return "signed" }
        if s.vendor != nil { return "vendor" }
        return "other"
    }

    private static func categoryLabel(_ key: String) -> String {
        switch key {
        case "tag", "finder": return "Takip / Bulucu"
        case "audio-personal": return "Kulaklık / Ses"
        case "audio-speaker": return "Hoparlör"
        case "phone": return "Telefon"
        case "watch", "wearable": return "Giyilebilir"
        case "ap": return "Access Point"
        case "hotspot", "wifi-direct": return "Hotspot"
        case "vehicle": return "Araç"
        case "drone": return "Drone"
        case "camera": return "Kamera"
        case "beacon": return "Beacon"
        case "hid", "mouse", "keyboard", "gamepad": return "Girdi Cihazı"
        case "computer": return "Bilgisayar"
        case "health", "sensor": return "Sensör / Sağlık"
        case "lock", "access": return "Kilit"
        case "tv", "display": return "Ekran / TV"
        case "printer": return "Yazıcı"
        case "thermostat", "iot", "home": return "Akıllı Ev"
        case "hacking", "pentest": return "Pentest"
        case "mesh": return "Mesh"
        case "glasses": return "Gözlük"
        case "garage", "fan", "light": return "Ev / Diğer IoT"
        case "siri": return "Siri"
        case "clock": return "Saat"
        case "module", "roadside", "acoustic": return "Altyapı"
        case "signed": return "İmzalı Cihazlar"
        case "vendor": return "Üreticisi Bilinen"
        default: return "Diğer"
        }
    }

    private var groups: [(key: String, items: [Sighting])] {
        let dict = Dictionary(grouping: viewModel.filteredSightings, by: Self.categoryKey)
        return dict.map { (key: $0.key, items: $0.value.sorted { $0.lastRssi > $1.lastRssi }) }
            .sorted { Self.categoryLabel($0.key) < Self.categoryLabel($1.key) }
    }

    public var body: some View {
        NavigationView {
            List {
                if groups.isEmpty {
                    Text("Henüz cihaz yok. Tara'ya bas.")
                        .foregroundColor(.secondary)
                }
                ForEach(groups, id: \.key) { group in
                    Section("\(Self.categoryLabel(group.key)) (\(group.items.count))") {
                        ForEach(group.items) { s in
                            Button {
                                selectedSighting = s
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.displayName)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(s.subtitle)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(s.lastRssi)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kategoriler")
        }
    }
}
