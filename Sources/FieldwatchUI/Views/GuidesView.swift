//
//  GuidesView.swift
//  Fieldwatch
//
//  Security guides: Lockdown, profiles, analytics, permissions,
//  battery, Apple tracker flow. Content-only, always safe.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct Guide: Identifiable {
    public var id: String { title }
    public let title: String
    public let body: String
}

public let SecurityGuides: [Guide] = [
    Guide(title: "Kilitlenme Modu (yüksek risk)",
          body: "Gazeteci/aktivist/seyahette riskli profilseniz: Ayarlar > Gizlilik ve Güvenlik > Kilitlenme Modu'nu açın. Mesaj eklerini, web JIT'i, bilinmeyen FaceTime aramalarını ve yeni profil kurulumunu kapatır. Günlük kullanımda bazı site/uygulama bozar; risk yoksa kapalı tutun."),
    Guide(title: "Profil / MDM denetimi",
          body: "Ayarlar > Genel > VPN ve Aygıt Yönetimi'ne bakın. Tanımadığınız profil, MDM kaydı veya kök sertifika varsa cihazınız uzaktan yönetiliyor olabilir. Şirket telefonu değilse ve tanımıyorsanız silin; emin değilseniz BT ekibinize sorun. Uygulamalar profil listesini göremez, elle bakmak gerekir."),
    Guide(title: "Analitik ve çökme izleri",
          body: "Ayarlar > Gizlilik ve Güvenlik > Analitik > Analitik Verileri: panic-full, ResetCounter, SpringBoard çökmeleri sıklaşmışsa donanımsal/zararlı belirtisi olabilir. Şüpheli dönemde: ses tuşları + yan tuşla sysdiagnose alıp uzmana gönderin (Apple'ın önerdiği yol budur)."),
    Guide(title: "Mikrofon / kamera izinleri",
          body: "Ayarlar > Gizlilik ve Güvenlik > Mikrofon ve Kamera: tanımadığınız uygulamaların iznini kapatın. Turuncu/yeşil nokta çıktığında Denetim Merkezi'nde hangi uygulamanın kullandığını kontrol edin."),
    Guide(title: "Pil anomalisi",
          body: "Ayarlar > Pil: arka planda tanımadığınız uygulama tüketimi varsa inceleyin. Uygulamalar birbirinin pilini göremez; bu liste tek kaynaktır."),
    Guide(title: "Apple takipçi uyarıları",
          body: "Ayarlar > Gizlilik ve Güvenlik > Konum Servisleri açık + Sistem Servisleri > Önemli Konumlar açık + Bluetooth açık + Bildirimler > İzleme Bildirimleri'ne izin verin. Yabancı AirTag sizinle hareket ederse iOS kendisi 'Sizinle Hareket Eden Bulundu' uyarısı verir; Harita + Ses Çal + NFC ile seri no okuma sistem ekranından yapılır."),
    Guide(title: "DNS güvenliği",
          body: "Bağlı WiFi'da ⓘ > DNS'i Yapılandır: tanımadığınız elle DNS varsa Otomatik'e alın. Ayarlar > Genel > VPN, DNS ve Aygıt Yönetimi > DNS altında bilmediğiniz profil varsa kaldırın. Araçlar > Ağ Denetimi ile kaçırma testi yapabilirsiniz."),
]

public struct GuidesView: View {
    public init() {}

    public var body: some View {
        List {
            Section {
                Text("Telefonun kendi güvenliği için adım adım kontroller. Bunlar sistem ayarlarıdır; uygulama adınıza işlem yapmaz.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(SecurityGuides) { guide in
                NavigationLink {
                    ScrollView {
                        Text(guide.body)
                            .padding()
                    }
                    .navigationTitle(guide.title)
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text(guide.title)
                }
            }
        }
        .navigationTitle("Güvenlik Rehberleri")
    }
}
