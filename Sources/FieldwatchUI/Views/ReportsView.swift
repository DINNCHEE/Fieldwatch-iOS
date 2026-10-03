//
//  ReportsView.swift
//  Fieldwatch
//
//  Observation sessions (sits): record, review, export, delete.
//

import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

public struct ReportsView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @State private var sits: [SitSession] = SitStore.shared.all()
    @State private var newName: String = ""
    @State private var shareText: String = ""
    @State private var showingShare = false

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private func hourBuckets() -> [Int] {
        var buckets = [Int](repeating: 0, count: 24)
        let now = Date()
        let calendar = Calendar.current
        let nowHour = calendar.component(.hour, from: now)
        for s in viewModel.sightings.values {
            let age = now.timeIntervalSince(s.firstSeen)
            guard age >= 0, age < 24 * 3600 else { continue }
            let h = calendar.component(.hour, from: s.firstSeen)
            let idx = (h - nowHour + 23 + 48) % 24
            buckets[idx] += 1
        }
        return buckets
    }

    public var body: some View {
        NavigationView {
            List {
                Section("Yeni Oturum") {
                    HStack {
                        TextField("Oturum adı", text: $newName)
                        Button(viewModel.activeSit == nil ? "Başlat" : "Bitir") {
                            if viewModel.activeSit == nil {
                                viewModel.startSit(name: newName.isEmpty ? "Oturum" : newName)
                                newName = ""
                            } else {
                                viewModel.endSit()
                            }
                            sits = SitStore.shared.all()
                        }
                        .fontWeight(.bold)
                    }
                    if let active = viewModel.activeSit {
                        Text("Kayıtta: \(active.name) · \(active.durationText)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("24 Saat Zaman Çizelgesi (ilk görülme)") {
                    let buckets = hourBuckets()
                    let peak = max(1, buckets.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<24, id: \.self) { h in
                            VStack(spacing: 2) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(buckets[h] > 0 ? Color.green : Color.gray.opacity(0.3))
                                    .frame(height: max(2, CGFloat(buckets[h]) / CGFloat(peak) * 64))
                                if h % 6 == 0 {
                                    Text("\(h)")
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 92)
                    Text("Son 24 saatte ilk kez görülen cihaz sayısı.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Oturumlar (\(sits.count))") {
                    if sits.isEmpty {
                        Text("Henüz oturum yok.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(sits) { sit in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sit.name)
                                    .font(.system(.body, weight: .semibold))
                                Spacer()
                                Text(sit.durationText)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Text("\(sit.deviceCount) cihaz · \(sit.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !sit.topDevices.isEmpty {
                                Text(sit.topDevices.prefix(3).joined(separator: " · "))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            HStack {
                                Button("Paylaş") {
                                    shareText = SitStore.shared.exportJSON(sit)
                                    showingShare = true
                                }
                                .font(.caption)
                                Spacer()
                                Button("Sil", role: .destructive) {
                                    SitStore.shared.delete(sit)
                                    sits = SitStore.shared.all()
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Raporlar")
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: [shareText])
            }
            .onAppear { sits = SitStore.shared.all() }
        }
    }
}
