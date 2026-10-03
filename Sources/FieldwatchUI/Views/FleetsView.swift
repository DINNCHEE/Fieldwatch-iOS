//
//  FleetsView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct FleetsView: View {
    @State private var fleets: [Fleet] = SignatureEngine.shared.activeFleets
    @State private var searchText = ""
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Fieldwatch contains 250+ signature fleets to automatically identify known RF transmitters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        }
    }
}
