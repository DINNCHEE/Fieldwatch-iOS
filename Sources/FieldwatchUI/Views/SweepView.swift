//
//  SweepView.swift
//  Fieldwatch
//
//  Bug-sweep mode: walk the room, find hidden cameras, mics, trackers.
//  Counter-surveillance — it finds devices watching YOU.
//

import SwiftUI
import CoreNFC
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

final class NfcRoomReader: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    @Published var lastTag: String?
    private var session: NFCNDEFReaderSession?

    func scan() {
        guard NFCNDEFReaderSession.readingAvailable else {
            lastTag = "Bu cihaz NFC okumuyor."
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Oda etiketine yaklaştır"
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let text = messages.first?.records.compactMap {
            String(data: $0.payload, encoding: .utf8)
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            self.lastTag = (text?.isEmpty == false) ? text : "Etiket okundu (boş içerik)"
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // User cancel is normal; keep last tag.
    }
}

public enum SweepTarget: String, CaseIterable, Sendable {
    case cameras = "Kameralar"
    case trackers = "Takipçiler"
    case audio = "Mikrofon / Ses"
    case all = "Tümü"

    var buckets: Set<String> {
        switch self {
        case .cameras: return ["camera"]
        case .trackers: return ["tag", "finder"]
        case .audio: return ["audio-personal", "audio-speaker", "siri", "hid"]
        case .all: return ["camera", "tag", "finder", "audio-personal",
                           "audio-speaker", "siri", "hid", "beacon", "sensor"]
        }
    }

    var advice: String {
        switch self {
        case .cameras: return "Odayı yavaşça gez. Sinyal güçlendikçe kaynağa yaklaşıyorsun. Duman dedektörü, priz, saat, ayna kenarlarına bak."
        case .trackers: return "Üzerinde/çantanda bilmediğin tag var mı diye bak. Hareket halindeyken seninle gelen cihaz kırmızıyla işaretlenir."
        case .audio: return "Sürekli yayın yapan ses cihazları burada listelenir. GSM böcekler (hücresel) RF ile bulunamaz."
        case .all: return "Şüpheli tüm yayıncılar. Güçlü sinyal = yakın mesafe."
        }
    }
}

public struct SweepView: View {
    @ObservedObject var viewModel: FieldwatchViewModel
    @State private var target: SweepTarget = .cameras
    @State private var sweeping: Bool = false
    @State private var startedAt: Date?
    @State private var elapsed: String = ""
    @State private var timer: Timer?
    @State private var showingShare = false
    @State private var shareText = ""
    @StateObject private var nfc = NfcRoomReader()

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private var matches: [Sighting] {
        viewModel.filteredSightings.filter { s in
            s.roleHints.contains { target.buckets.contains($0.bucket) }
        }.sorted { $0.lastRssi > $1.lastRssi }
    }

    private var strongest: Sighting? { matches.first }

    public var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Hedef", selection: $target) {
                    ForEach(SweepTarget.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Text(target.advice)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if let top = strongest {
                    VStack(spacing: 4) {
                        Text("EN GÜÇLÜ SİNYAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                        Text(top.displayName)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .lineLimit(1)
                        Text("\(top.lastRssi) dBm · \(DeviceExplain.rssiBand(rssi: top.lastRssi))")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundColor(.red)
                        if top.isCoTraveling {
                            Text("SENİNLE HAREKET EDİYOR")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    Text(sweeping ? "Dinleniyor… şüpheli yayın yok." : "Başlamak için Süpür'e bas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }

                HStack {
                    Button(sweeping ? "Durdur" : "Süpür") {
                        if sweeping {
                            sweeping = false
                            timer?.invalidate()
                        } else {
                            viewModel.startAllScans()
                            sweeping = true
                            startedAt = Date()
                            timer?.invalidate()
                            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                                if let start = startedAt {
                                    let s = Int(Date().timeIntervalSince(start))
                                    elapsed = "\(s / 60):\(String(format: "%02d", s % 60))"
                                }
                            }
                        }
                    }
                    .fontWeight(.bold)
                    Spacer()
                    if sweeping {
                        Text(elapsed)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Button("Özet Paylaş") {
                        shareText = summary()
                        showingShare = true
                    }
                    .font(.caption)
                    Button("NFC Oda Etiketi") {
                        nfc.scan()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                if let tag = nfc.lastTag {
                    Text("Oda: \(tag)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                }

                List {
                    Section("Şüpheliler (\(matches.count))") {
                        ForEach(matches) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.displayName)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .lineLimit(1)
                                    Text(s.subtitle)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(s.lastRssi)")
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .foregroundColor(s.lastRssi > -60 ? .red : .primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Böcek Süpürme")
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: [shareText])
            }
            .onDisappear {
                timer?.invalidate()
                sweeping = false
            }
        }
    }

    private func summary() -> String {
        var lines = ["Fieldwatch süpürme özeti", "Hedef: \(target.rawValue)",
                     "Süre: \(elapsed.isEmpty ? "-" : elapsed)"]
        if let tag = nfc.lastTag {
            lines.append("Oda etiketi: \(tag)")
        }
        lines.append("")
        if matches.isEmpty {
            lines.append("Şüpheli yayın bulunamadı. (Not: hücresel/GSM böcekler RF ile görünmez.)")
        } else {
            for s in matches.prefix(20) {
                lines.append("- \(s.displayName) [\(s.identifier)] \(s.lastRssi) dBm \(s.isCoTraveling ? "HAREKETLİ" : "")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
