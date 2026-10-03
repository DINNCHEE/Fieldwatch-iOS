//
//  ChannelChartView.swift
//  Fieldwatch
//
//  Wi-Fi channel occupancy from companion observations.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct ChannelChartView: View {
    @ObservedObject var viewModel: FieldwatchViewModel

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private var counts: [(channel: Int, count: Int)] {
        var dict: [Int: Int] = [:]
        for s in viewModel.filteredSightings where s.kind == .wifi {
            if let ch = s.channel { dict[ch, default: 0] += 1 }
        }
        return dict.sorted { $0.key < $1.key }.map { (channel: $0.key, count: $0.value) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if counts.isEmpty {
                Text("Kanal bilgisi yok. Companion (ESP32) veya TrollStore ile Wi-Fi taramasında dolar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                let peak = max(1, counts.map { $0.count }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(counts, id: \.channel) { entry in
                        VStack(spacing: 2) {
                            Text("\(entry.count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(entry.channel <= 14 ? Color.green : Color.cyan)
                                .frame(height: max(4, CGFloat(entry.count) / CGFloat(peak) * 80))
                            Text("\(entry.channel)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 120)
                .padding(.horizontal)
                Text("Yeşil: 2.4 GHz · Camgöbeği: 5/6 GHz")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .navigationTitle("Kanal Doluluk")
        .navigationBarTitleDisplayMode(.inline)
    }
}
