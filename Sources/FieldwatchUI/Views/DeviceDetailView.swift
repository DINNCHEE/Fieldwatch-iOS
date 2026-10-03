//
//  DeviceDetailView.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
import UIKit
import PhotosUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(parent: PhotoPicker) { self.parent = parent }

        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let item = results.first else { return }
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.onPick(image)
                        }
                    }
                }
            }
        }
    }
}

public struct EvidenceStore {
    public static func dir(id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("evidence", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func save(id: String, image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let url = dir(id: id).appendingPathComponent("\(UUID().uuidString).jpg")
        try? data.write(to: url, options: .atomic)
    }

    public static func load(id: String) -> [UIImage] {
        let dirURL = dir(id: id)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { UIImage(data: $0) }
    }
}

public struct DeviceDetailView: View {
    let sighting: Sighting
    @ObservedObject var viewModel: FieldwatchViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingHuntView = false
    @State private var customName: String = ""
    @State private var customNotes: String = ""
    @State private var bookmarked: Bool = false
    @State private var alertOn: Bool = false
    @State private var copied: Bool = false
    @State private var wigleResult: WigleResult?
    @State private var wigleError: String?
    @State private var wigleLoading: Bool = false
    @State private var gattInfo: GattInfo?
    @State private var gattLoading: Bool = false
    @State private var gattFailed: Bool = false
    @State private var nvdResults: [NvdVuln]?
    @State private var nvdLoading: Bool = false
    @State private var evidenceImages: [UIImage] = []
    @State private var showingPicker: Bool = false
    
    public init(sighting: Sighting, viewModel: FieldwatchViewModel) {
        self.sighting = sighting
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            List {
                // Header Card
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(sighting.displayName)
                                .font(.system(.title2, design: .monospaced))
                                .fontWeight(.bold)
                            Spacer()
                            Text(sighting.kind.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(sighting.kind == .wifi ? Color.cyan.opacity(0.2) : Color.blue.opacity(0.2))
                                .foregroundColor(sighting.kind == .wifi ? .cyan : .blue)
                                .cornerRadius(6)
                        }
                        
                        Text(sighting.identifier)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let vendor = sighting.vendor, !vendor.isEmpty {
                            Text(vendor)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        
                        if sighting.isCoTraveling {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("MOVING WITH YOU - POTENTIAL TAIL")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Identity guess (what the radio is advertising)
                Section("What This Looks Like") {
                    let guessNames: [String] = sighting.fleetName.map { [$0] } ?? []
                    let guess = DeviceExplain.guess(sighting: sighting, signatureNames: guessNames)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guess.headline)
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                        Text(guess.because)
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                        Text("Confidence: \(guess.confidence.rawValue)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // My label (name, notes, watch, alert) — persisted
                Section("Benim Etiketim") {
                    TextField("Özel isim", text: $customName)
                        .onSubmit { saveCustom() }
                    TextField("Not", text: $customNotes)
                        .onSubmit { saveCustom() }
                    Toggle("İzle (yıldızla)", isOn: $bookmarked)
                        .onChange(of: bookmarked, perform: { _ in saveCustom() })
                    Toggle("Görülünce uyar", isOn: $alertOn)
                        .onChange(of: alertOn, perform: { _ in saveCustom() })
                    Button("Kaydet") { saveCustom() }
                    if copied {
                        Text("Kopyalandı ✓")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .onAppear {
                    if let c = Persistence.shared.custom(id: sighting.identifier) {
                        customName = c.customName ?? ""
                        customNotes = c.notes ?? ""
                        bookmarked = c.bookmarked
                        alertOn = c.alertEnabled
                    }
                }

                // GATT read (BLE, connectable only): real manufacturer/model/serial.
                if sighting.kind == .ble && sighting.facts.isConnectable == true {
                    Section("GATT Bilgisi") {
                        if gattLoading {
                            Text("Okunuyor… (10 sn)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let g = gattInfo {
                            if let m = g.manufacturer {
                                HStack { Text("Üretici"); Spacer(); Text(m).font(.caption.monospaced()) }
                            }
                            if let m = g.model {
                                HStack { Text("Model"); Spacer(); Text(m).font(.caption.monospaced()) }
                            }
                            if let s = g.serial {
                                HStack { Text("Seri"); Spacer(); Text(s).font(.caption.monospaced()) }
                            }
                            if let f = g.firmware {
                                HStack { Text("Firmware"); Spacer(); Text(f).font(.caption.monospaced()) }
                            }
                            if !g.services.isEmpty {
                                Text("Servisler: \(g.services.joined(separator: ", "))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button("Cihaza Bağlanıp Oku") {
                                gattFailed = false
                                gattLoading = true
                                BleScanner.shared.readGatt(id: sighting.identifier) { info in
                                    gattInfo = info
                                    gattFailed = (info == nil)
                                    gattLoading = false
                                }
                            }
                            if gattFailed {
                                Text("Okunamadı (cihaz reddetti veya menzilden çıktı).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("Kısa süreli bağlanır, bilgileri okur, hemen ayrılır.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Evidence photos
                Section("Kanıt Fotoğrafları (\(evidenceImages.count))") {
                    if !evidenceImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(evidenceImages.indices, id: \.self) { idx in
                                    Image(uiImage: evidenceImages[idx])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .frame(height: 110)
                    }
                    Button("Fotoğraf Ekle") { showingPicker = true }
                }
                .sheet(isPresented: $showingPicker) {
                    PhotoPicker(isPresented: $showingPicker) { image in
                        EvidenceStore.save(id: sighting.identifier, image: image)
                        evidenceImages = EvidenceStore.load(id: sighting.identifier)
                    }
                }
                .onAppear {
                    evidenceImages = EvidenceStore.load(id: sighting.identifier)
                }

                // NVD firmware CVE lookup
                Section("Güvenlik Açığı (NVD)") {
                    if nvdLoading {
                        Text("Aranıyor…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let vulns = nvdResults {
                        if vulns.isEmpty {
                            Text("Kayıtlı açık bulunamadı (veya eşleşme yok).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ForEach(vulns.prefix(10)) { vuln in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(vuln.cveId)
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                    Spacer()
                                    if let score = vuln.cvss {
                                        Text(String(format: "%.1f", score))
                                            .font(.caption.monospaced())
                                            .foregroundColor(score >= 7 ? .red : .secondary)
                                    }
                                }
                                Text(vuln.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    } else {
                        Button("Bu Cihazda Açık Ara") {
                            nvdLoading = true
                            Task {
                                let query = [sighting.vendor, sighting.fleetName, sighting.name]
                                    .compactMap { $0 }.joined(separator: " ")
                                let results = await NvdLookup.search(model: query)
                                await MainActor.run {
                                    nvdResults = results ?? []
                                    nvdLoading = false
                                }
                            }
                        }
                        Text("Kaynak: NIST NVD (ücretsiz, anahtarsız).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Hunt & Locate action
                Section {
                    Button {
                        viewModel.huntTargetId = sighting.identifier
                        showingHuntView = true
                    } label: {
                        HStack {
                            Image(systemName: "scope")
                                .font(.title3)
                            Text("Launch Proximity Hunt Mode")
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(.green)
                    }
                }

                // Network actions (Wi-Fi only): copy ID + open router panel.
                // iPhone cannot kick devices (no packet injection); blocking
                // is done in your own router's admin page.
                if sighting.kind == .wifi {
                    Section("Ağ İşlemleri") {
                        if let ch = sighting.channel {
                            HStack {
                                Text("Kanal")
                                Spacer()
                                Text(Self.bandText(channel: ch)).font(.caption.monospaced())
                            }
                        }
                        if RadioDb.shared.isRandomized(sighting.identifier) {
                            Text("Lokal yönetimli BSSID: sanal/misafir ağ olabilir, OUI üretici bilgisi gerçek olmayabilir.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Button {
                            UIPasteboard.general.string = "\(sighting.displayName)\n\(sighting.identifier)"
                            copied = true
                        } label: {
                            Text("MAC / IP Kopyala")
                        }
                        if let gw = LanDiscovery.shared.lastGateway,
                           let url = URL(string: "http://\(gw)") {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Text("Router Panelini Aç (\(gw))")
                            }
                        }
                        Text("Not: iPhone cihaz düşüremez. Engellemek için router panelinden MAC engelleme yap.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section("Wigle Veritabanı") {
                        if !WigleLookup.hasCredentials {
                            Text("Bilinmeyen ağı sorgulamak için Ayarlar > Wigle Arama'ya ücretsiz API anahtarını gir (wigle.net/account). Veriler © WiGLE.net.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button(wigleLoading ? "Aranıyor…" : "Wigle'da Ara (BSSID)") {
                            lookupWigle()
                        }
                        .disabled(wigleLoading || !WigleLookup.hasCredentials)
                        if let r = wigleResult {
                            if let coords = r.coordinateText {
                                HStack {
                                    Text("Tahmini konum")
                                    Spacer()
                                    Text(coords).font(.caption.monospaced())
                                }
                                if let lat = r.latitude, let lon = r.longitude,
                                   let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)") {
                                    Button {
                                        UIApplication.shared.open(url)
                                    } label: {
                                        Text("Haritada Aç")
                                    }
                                }
                            }
                            if let city = r.city {
                                HStack {
                                    Text("Şehir")
                                    Spacer()
                                    Text([city, r.region, r.country].compactMap { $0 }.joined(separator: " / "))
                                        .font(.caption)
                                }
                            }
                            if let enc = r.encryption {
                                HStack {
                                    Text("Şifreleme")
                                    Spacer()
                                    Text(enc).font(.caption.monospaced())
                                }
                            }
                            if let first = r.firstSeen {
                                HStack {
                                    Text("İlk görülme")
                                    Spacer()
                                    Text(first).font(.caption.monospaced())
                                }
                            }
                        }
                        if let e = wigleError {
                            Text(e)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Text("Kaynak: WiGLE.net (kullanıcının kendi anahtarı, tekil sorgu).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Role Hints
                if !sighting.roleHints.isEmpty {
                    Section("Role & Intelligence Hints") {
                        ForEach(sighting.roleHints, id: \.self) { hint in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.label)
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                                Text(hint.reason)
                                    .font(.system(.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Decoded RF Payload
                if !sighting.decodedFields.isEmpty {
                    Section("Decoded Payload Fields") {
                        ForEach(sighting.decodedFields, id: \.self) { field in
                            HStack {
                                Text(field.label)
                                    .font(.system(.caption))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(field.value)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                
                // Signal & Timing
                Section("RF Observations & Metrics") {
                    HStack {
                        Text("Current RSSI")
                        Spacer()
                        Text("\(sighting.lastRssi) dBm")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    HStack {
                        Text("Peak RSSI")
                        Spacer()
                        Text("\(sighting.maxRssi) dBm")
                            .font(.system(.body, design: .monospaced))
                    }
                    if let connectable = sighting.facts.isConnectable {
                        HStack {
                            Text("Bağlanabilir (BLE)")
                            Spacer()
                            Text(connectable ? "Evet" : "Hayır")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    HStack {
                        Text("Observed Packets")
                        Spacer()
                        Text("\(sighting.count)")
                            .font(.system(.body, design: .monospaced))
                    }
                    let recentSamples = sighting.rssiSamples.filter {
                        Date().timeIntervalSince($0.at) < 60
                    }
                    if !recentSamples.isEmpty {
                        HStack {
                            Text("Yayın hızı")
                            Spacer()
                            Text("\(recentSamples.count)/dk\(recentSamples.count > 30 ? " (yoğun!)" : "")")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(recentSamples.count > 30 ? .red : .primary)
                        }
                    }
                    HStack {
                        Text("First Seen")
                        Spacer()
                        Text(sighting.firstSeen.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospaced())
                    }
                    HStack {
                        Text("Last Seen")
                        Spacer()
                        Text(sighting.lastSeen.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospaced())
                    }
                }
                
                // Raw Manufacturer Records
                if !sighting.facts.mfgRecords.isEmpty {
                    Section("Raw Manufacturer Records") {
                        ForEach(sighting.facts.mfgRecords, id: \.self) { mfg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Company ID: 0x\(String(format: "%04X", mfg.companyId))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(mfg.dataHex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Location Information
                if let loc = sighting.location {
                    Section("GPS Observation") {
                        HStack {
                            Text("Coordinates")
                            Spacer()
                            Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                .font(.caption.monospaced())
                        }
                        HStack {
                            Text("Tracked GPS Fixes")
                            Spacer()
                            Text("\(sighting.locationHistory.count)")
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingHuntView) {
                HuntView(sighting: sighting, viewModel: viewModel)
            }
        }
    }

    private static func bandText(channel ch: Int) -> String {
        if ch == 14 { return "14 · 2.4 GHz (2484 MHz)" }
        if (1...13).contains(ch) { return "\(ch) · 2.4 GHz (\(2412 + (ch - 1) * 5) MHz)" }
        return "\(ch) · 5/6 GHz (~\(5000 + ch * 5) MHz)"
    }

    private func saveCustom() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = customNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty && notes.isEmpty && !bookmarked && !alertOn {
            Persistence.shared.removeCustom(id: sighting.identifier)
        } else {
            Persistence.shared.setCustom(CustomDevice(
                id: sighting.identifier,
                customName: name.isEmpty ? nil : name,
                notes: notes.isEmpty ? nil : notes,
                bookmarked: bookmarked,
                alertEnabled: alertOn
            ))
        }
        if alertOn { Alerter.requestNotificationPermission() }
    }

    private func lookupWigle() {
        wigleError = nil
        wigleResult = nil
        wigleLoading = true
        Task {
            do {
                let result = try await WigleLookup.search(bssid: sighting.identifier)
                await MainActor.run {
                    wigleResult = result
                    wigleLoading = false
                }
            } catch let error as WigleError {
                await MainActor.run {
                    switch error {
                    case .noCredentials: wigleError = "Önce Ayarlar'a API anahtarı gir."
                    case .rateLimited: wigleError = "Günlük sorgu limiti doldu, yarın dene."
                    case .notFound: wigleError = "Bu BSSID Wigle'da yok."
                    case .network(let msg): wigleError = "Ağ hatası: \(msg)"
                    case .decoding: wigleError = "Yanıt çözümlenemedi."
                    }
                    wigleLoading = false
                }
            } catch {
                await MainActor.run {
                    wigleError = error.localizedDescription
                    wigleLoading = false
                }
            }
        }
    }
}
