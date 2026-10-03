//
//  ReportsView.swift
//  Fieldwatch
//
//  Observation sessions (sits): record, review, export, delete.
//

import SwiftUI
import UIKit
import CoreImage
import CoreLocation
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
                        NavigationLink {
                            SitDetailView(sit: sit, viewModel: viewModel, onDelete: {
                                SitStore.shared.delete(sit)
                                sits = SitStore.shared.all()
                            })
                        } label: {
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
                            }
                            .padding(.vertical, 4)
                        }
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

public struct SitDetailView: View {
    let sit: SitSession
    @ObservedObject var viewModel: FieldwatchViewModel
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingShare = false
    @State private var shareItems: [Any] = []
    @State private var qrImage: UIImage?
    @State private var status = ""

    public var body: some View {
        List {
            if !sit.path.isEmpty {
                Section("Yol (\(sit.path.count) nokta)") {
                    SharedMap(
                        trail: sit.path.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                        },
                        points: []
                    )
                    .frame(height: 240)
                    .cornerRadius(12)
                }
            }

            Section("Cihazlar") {
                ForEach(sit.topDevices.prefix(10), id: \.self) { device in
                    Text(device)
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            if let qr = qrImage {
                Section("QR") {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                }
            }

            Section("Dışa Aktar") {
                Button("GPX Olarak Paylaş") {
                    shareItems = [SitExport.gpx(sit: sit)]
                    showingShare = true
                }
                Button("PDF Rapor Paylaş") {
                    if let url = SitExport.pdf(sit: sit) {
                        shareItems = [url]
                        showingShare = true
                    } else {
                        status = "PDF oluşturulamadı."
                    }
                }
                Button("QR Kod Oluştur") {
                    qrImage = SitExport.qr(sit: sit)
                }
                Button("Wigle'a Yükle (gerçek MAC'li WiFi)") {
                    status = "Hazırlanıyor…"
                    Task {
                        let rows = viewModel.sightings.values.filter {
                            $0.kind == .wifi && $0.location != nil &&
                            WigleUpload.isRealMac($0.identifier)
                        }
                        if rows.isEmpty {
                            await MainActor.run { status = "Yüklenecek gerçek MAC'li WiFi yok." }
                            return
                        }
                        let csv = WigleUpload.buildCSV(sightings: Array(rows))
                        do {
                            let msg = try await WigleUpload.upload(csv: csv)
                            await MainActor.run { status = msg }
                        } catch let error as WigleUpload.UploadError {
                            await MainActor.run {
                                switch error {
                                case .noCredentials: status = "Önce Ayarlar'a Wigle anahtarı gir."
                                case .nothingToUpload: status = "Yüklenecek veri yok."
                                case .failed(let m): status = "Hata: \(m)"
                                }
                            }
                        } catch {
                            await MainActor.run { status = error.localizedDescription }
                        }
                    }
                }
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("Oturumu Sil", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(sit.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: shareItems)
        }
    }
}

public struct SitExport: Sendable {
    public static func gpx(sit: SitSession) -> String {
        let formatter = ISO8601DateFormatter()
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"Fieldwatch-iOS\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        out += "<trk><name>\(sit.name.xmlEscaped)</name><trkseg>\n"
        for p in sit.path {
            out += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(p.alt)</ele><time>\(formatter.string(from: p.at))</time></trkpt>\n"
        }
        out += "</trkseg></trk>\n"
        for device in sit.topDevices {
            out += "<!-- \(device.xmlEscaped) -->\n"
        }
        out += "</gpx>"
        return out
    }

    public static func pdf(sit: SitSession) -> URL? {
        let meta = [
            "Oturum: \(sit.name)",
            "Başlangıç: \(sit.startedAt.formatted(date: .abbreviated, time: .shortened))",
            "Süre: \(sit.durationText)",
            "Cihaz: \(sit.deviceCount)",
            "Nokta: \(sit.path.count)",
        ]
        let format = UIGraphicsPDFRendererFormat()
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 40
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
            ("Fieldwatch Raporu" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttrs)
            y += 36
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            for line in meta {
                (line as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttrs)
                y += 20
            }
            y += 12
            ("Cihazlar" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttrs)
            y += 28
            let smallAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
            for device in sit.topDevices.prefix(60) {
                if y > 800 {
                    context.beginPage()
                    y = 40
                }
                (String(device.prefix(90)) as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: smallAttrs)
                y += 15
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fieldwatch-\(sit.id.uuidString).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    public static func qr(sit: SitSession) -> UIImage? {
        let payload = "fieldwatch-sit:\(sit.id.uuidString):\(sit.name):\(sit.deviceCount)"
        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
