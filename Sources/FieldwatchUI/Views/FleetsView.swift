//
//  FleetsView.swift
//  Fieldwatch
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct FleetsView: View {
    @State private var fleets: [Fleet] = SignatureEngine.shared.activeFleets
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newGlob = ""

    public init() {}

    private var customIds: Set<String> {
        Set(SignatureEngine.shared.customFleets.map { $0.id })
    }

    private func reload() {
        fleets = SignatureEngine.shared.activeFleets
    }

    public var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Fieldwatch contains 250+ signature fleets to automatically identify known RF transmitters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Özel İmzalarım") {
                    Button("+ Yeni İmza (isim kalıbı)") {
                        showingAdd = true
                    }
                    .font(.caption)
                    ForEach(fleets.filter { customIds.contains($0.id) }) { fleet in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fleet.name)
                                    .font(.system(.body, weight: .semibold))
                                Text("özel kural")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Sil", role: .destructive) {
                                SignatureEngine.shared.deleteCustomFleet(id: fleet.id)
                                reload()
                            }
                            .font(.caption)
                        }
                    }
                }

                ForEach($fleets) { $fleet in
                    if searchText.isEmpty || fleet.name.localizedCaseInsensitiveContains(searchText) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fleet.name)
                                    .font(.system(.body, weight: .semibold))
                                Text("\(fleet.rules.count) signature rules (\(fleet.matchAny ? "Match Any" : "Match All"))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $fleet.enabled)
                                .labelsHidden()
                                .onChange(of: fleet.enabled, perform: { val in
                                    SignatureEngine.shared.toggleFleet(id: fleet.id, enabled: val)
                                })
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Fleets...")
            .navigationTitle("Signature Fleets (\(fleets.count))")
            .sheet(isPresented: $showingAdd) {
                NavigationView {
                    Form {
                        TextField("İmza adı", text: $newName)
                        TextField("İsim kalıbı (örn. Ruuvi*)", text: $newGlob)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Button("Ekle") {
                            SignatureEngine.shared.addCustomFleet(name: newName, glob: newGlob)
                            newName = ""
                            newGlob = ""
                            showingAdd = false
                            reload()
                        }
                    }
                    .navigationTitle("Yeni İmza")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
