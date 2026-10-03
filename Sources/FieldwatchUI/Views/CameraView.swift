//
//  CameraView.swift
//  Fieldwatch
//
//  Your own network cameras: auto-detected list, one-tap admin page,
//  snapshot preview with your credentials. No credential guessing,
//  no bypass — the camera must accept YOUR login.
//

import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

// MARK: - Camera detection

func isCameraLike(_ s: Sighting) -> Bool {
    guard s.kind == .wifi else { return false }
    if s.roleHints.contains(where: { $0.bucket == "camera" }) { return true }
    let hay = "\(s.displayName) \(s.fleetName ?? "") \(s.name ?? "")".lowercased()
    for key in ["kamera", "camera", "cam", "onvif", "rtsp",
                "arlo", "wyze", "tapo", "hikvision", "dahua", "reolink",
                "amcrest", "axis", "uniview", "hanwha", "wisenet", "lorex",
                "swann", "eufy", "blink", "ubiquiti", "protect", "nest",
                "ring", "foscam", "tp-link tapo", "xiaomi", "360"] {
        if hay.contains(key) { return true }
    }
    return false
}

// MARK: - Snapshot loader (auth-aware)

final class CameraLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var image: UIImage?
    @Published var stateText: String = "hazır"

    private var user = ""
    private var pass = ""
    private var session: URLSession?
    private var timer: Timer?
    private var host = ""
    private var sightingId = ""
    private var active = false

    private static let candidates = [
        "/snapshot.jpg", "/snapshot.cgi", "/cgi-bin/snapshot.cgi?1",
        "/image.jpg", "/img/snapshot.cgi", "/tmpfs/auto.jpg",
        "/tmpfs/snap.jpg", "/ISAPI/Streaming/channels/101/picture",
        "/snap.jpg", "/live/0/jpeg.jpg", "/axis-cgi/jpg/image.cgi",
        "/onvif/snapshot", "/cgi-bin/hi3510/param.cgi",
    ]

    func start(host: String, id: String, user: String, pass: String) {
        stop()
        self.host = host
        self.sightingId = id
        self.user = user
        self.pass = pass
        self.active = true
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        Task { await self.probeThenPoll() }
    }

    func stop() {
        active = false
        timer?.invalidate()
        timer = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.previousFailureCount == 0, !user.isEmpty {
            completionHandler(.useCredential,
                              URLCredential(user: user, password: pass, persistence: .none))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func fetch(url: URL) async -> UIImage? {
        guard let session = session else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard type.contains("image") || data.starts(with: [0xFF, 0xD8]) else { return nil }
            guard data.count > 1024 else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    @MainActor
    private func setState(_ text: String) { stateText = text }

    @MainActor
    private func setImage(_ img: UIImage?) { image = img }

    private func probeThenPoll() async {
        // Known-good URL first.
        if let known = CameraStore.snapshotURL(id: sightingId),
           let url = URL(string: known),
           let img = await fetch(url: url), active {
            await setImage(img)
            await setState("canlı")
            beginPoll(url: url)
            return
        }
        await setState("uyumlu adres aranıyor…")
        for path in Self.candidates {
            guard active, let url = URL(string: "http://\(host)\(path)") else { return }
            if let img = await fetch(url: url), active {
                CameraStore.saveSnapshotURL(id: sightingId, url: url.absoluteString)
                await setImage(img)
                await setState("canlı")
                beginPoll(url: url)
                return
            }
        }
        if active {
            await setState("Görüntü alınamadı (kimlik ya da uyumsuz adres).")
        }
    }

    private func beginPoll(url: URL) {
        Task { @MainActor in
            guard self.active else { return }
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self, self.active else { return }
                Task {
                    if let img = await self.fetch(url: url) {
                        await self.setImage(img)
                    }
                }
            }
        }
    }
}

// MARK: - List

public struct CameraView: View {
    @ObservedObject var viewModel: FieldwatchViewModel

    public init(viewModel: FieldwatchViewModel) {
        self.viewModel = viewModel
    }

    private var cameras: [Sighting] {
        viewModel.filteredSightings.filter(isCameraLike)
            .sorted { $0.lastRssi > $1.lastRssi }
    }

    public var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Ağında otomatik bulunan kameralar. Görüntü için kameranın kendi kullanıcı adı + şifren gerekir; tahmin/yüklenme denemez.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("Kameralar (\(cameras.count))") {
                    if cameras.isEmpty {
                        Text("Kamera bulunamadı. Tara açıkken ağa bağlı kameralar burada listelenir.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(cameras) { s in
                        NavigationLink {
                            CameraDetailView(sighting: s)
                        } label: {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.displayName)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .lineLimit(1)
                                    Text(s.identifier)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
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
            .navigationTitle("Kameralar")
        }
    }
}

// MARK: - Detail: snapshot + admin + credentials

public struct CameraDetailView: View {
    let sighting: Sighting
    @StateObject private var loader = CameraLoader()
    @State private var user = ""
    @State private var pass = ""
    @State private var hasCreds = false

    public init(sighting: Sighting) {
        self.sighting = sighting
    }

    public var body: some View {
        List {
            Section("Canlı Önizleme") {
                if let img = loader.image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    Text(loader.stateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button("Başlat") { startStream() }
                        .fontWeight(.bold)
                        .disabled(loader.image != nil)
                    Spacer()
                    Button("Durdur") { loader.stop() }
                        .font(.caption)
                }
                if let known = CameraStore.snapshotURL(id: sighting.identifier) {
                    Text(known)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Button("Adresi Unut (yeniden tara)") {
                        CameraStore.forgetSnapshotURL(id: sighting.identifier)
                    }
                    .font(.caption)
                }
            }

            Section("Kamera Girişi") {
                HStack {
                    Text("Kullanıcı")
                    Spacer()
                    TextField("admin", text: $user)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                HStack {
                    Text("Şifre")
                    Spacer()
                    SecureField("••••", text: $pass)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Kaydet") {
                        CameraStore.saveCredentials(id: sighting.identifier, user: user, pass: pass)
                        hasCreds = true
                    }
                    Spacer()
                    Button("Temizle", role: .destructive) {
                        CameraStore.clearCredentials(id: sighting.identifier)
                        user = ""
                        pass = ""
                        hasCreds = false
                    }
                }
                Text("Kilitli kasada saklanır. Yanlışsa kamera 401 döner, deneme yanılma yapılmaz.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Erişim") {
                if let url = URL(string: "http://\(sighting.identifier)") {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Text("Yönetim Sayfasını Aç (\(sighting.identifier))")
                    }
                }
                Text("Tarayıcıda kameranın kendi giriş ekranı açılır.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Cihaz") {
                HStack { Text("Ad"); Spacer(); Text(sighting.displayName).font(.caption.monospaced()) }
                HStack { Text("Kimlik"); Spacer(); Text(sighting.identifier).font(.caption.monospaced()) }
                if let ch = sighting.channel {
                    HStack { Text("Kanal"); Spacer(); Text("\(ch)").font(.caption.monospaced()) }
                }
                if let v = sighting.vendor {
                    HStack { Text("Üretici"); Spacer(); Text(v).font(.caption) }
                }
            }
        }
        .navigationTitle("Kamera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let creds = CameraStore.credentials(id: sighting.identifier) {
                user = creds.user
                pass = creds.pass
                hasCreds = true
            }
        }
        .onDisappear { loader.stop() }
    }

    private func startStream() {
        loader.start(host: sighting.identifier, id: sighting.identifier, user: user, pass: pass)
    }
}
