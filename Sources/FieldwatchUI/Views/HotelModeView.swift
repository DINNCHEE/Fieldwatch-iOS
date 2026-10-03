//
//  HotelModeView.swift
//  Fieldwatch
//
//  One-tap guided hotel/office check: network audit, camera sweep,
//  tracker sweep, then a session report.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct HotelModeView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @State private var netDone = false
    @State private var camDone = false
    @State private var tagDone = false

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section {
                Text("Otele/ofise girince sırayla yap: 1) Ağı denetle 2) Kameraları süpür 3) Takipçi tara 4) Oturumu kaydet. Hepsi bu uygulamada.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Adımlar") {
                NavigationLink {
                    EvilTwinView()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("1. Ağ denetimi")
                            Text("Sahte ikiz + DNS kaçırma testi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(netDone ? "Tamam ✓" : "Yapıldı işaretle") { netDone.toggle() }
                            .font(.caption)
                    }
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("2. Kamera süpürme")
                        Text("Süpürme sekmesi > Kameralar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(camDone ? "Tamam ✓" : "Yapıldı işaretle") { camDone.toggle() }
                        .font(.caption)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("3. Takipçi taraması")
                        Text("Süpürme sekmesi > Takipçiler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(tagDone ? "Tamam ✓" : "Yapıldı işaretle") { tagDone.toggle() }
                        .font(.caption)
                }
            }

            Section("Oturum") {
                HStack {
                    Button(viewModel.activeSit == nil ? "Denetim Oturumunu Başlat" : "Oturumu Bitir") {
                        if viewModel.activeSit == nil {
                            viewModel.startSit(name: "Otel Denetimi")
                        } else {
                            viewModel.endSit()
                        }
                    }
                    .fontWeight(.bold)
                    Spacer()
                    if let active = viewModel.activeSit {
                        Text(active.name)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                Text("Bitince Raporlar sekmesinde özet + paylaşım hazır olur.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Otel Modu")
        .navigationBarTitleDisplayMode(.inline)
    }
}
