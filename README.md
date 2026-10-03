# Fieldwatch iOS Port

Fieldwatch'in ([OffGridPete/Fieldwatch](https://github.com/OffGridPete/Fieldwatch)) **iOS (Swift & SwiftUI)** için optimize edilmiş, bağımsız ve tam teşekküllü entegrasyonudur.

> Orijinal proje Android için geliştirilmiş pasif bir Wi-Fi ve Bluetooth LE gözlemcisidir. Bu iOS portu, Apple ekosisteminin güvenlik modeli ve CoreBluetooth mimarisi dikkate alınarak tasarlanmıştır.

---

## ⚡ iOS Entegrasyonunun Temel Prensipleri ve Kısıtlamaları

Android ve iOS arasındaki temel RF/işletim sistemi farkları:

| Özellik | Android (Orijinal) | iOS Standart (App Store) | iOS Gelişmiş (Sideload / TrollStore / JB) |
|---|---|---|---|
| **BLE Tarama** | `BluetoothLeScanner` | `CoreBluetooth` (`CBCentralManager`) | `CoreBluetooth` |
| **Gerçek MAC (BD_ADDR)** | Görüntülenebilir | Apple tarafından rastgele **UUID** ile maskelenir | UUID (veya donanım köprüsü ile MAC) |
| **BLE Paket İçeriği** | Üretici verisi, ham baytlar | Manufacturer Data, Service Data, UUID'ler | Tam paket |
| **Wi-Fi AP Taraması** | `WifiManager.startScan()` | **Yasak** (Yalnızca bağlı AP SSID/BSSID) | `MobileWiFi.framework` (Özel API ile tam tarama) |
| **Harici Companion** | Gerek yok | Desteklenir (ESP32 Marauder / BLE Köprüsü) | Desteklenir |
| **GPS Eş-Seyahat (Tail)** | Var | Var (`CoreLocation` + Mesafe/Zaman Korelasyonu) | Var |
| **ATAK / CoT Yayını** | UDP Socket | Var (`Network.framework` ile CoT XML) | Var |

---

## 📂 Proje Mimarisi

```text
Fieldwatch-iOS/
├── Package.swift                    # Swift Package Manager tanımı
├── Info.plist                       # Gerekli iOS izinleri (BLE, GPS, Yerel Ağ)
├── Resources/
│   ├── fieldwatch-signatures-v2.json # 252+ Orijinal Cihaz Filosu ve Kuralı
│   └── radiodb.bin                  # IEEE OUI ve Bluetooth SIG ikili veritabanı
└── Sources/
    ├── FieldwatchCore/              # Çekirdek Domain & RF Mantığı
    │   ├── Models/Models.swift      # Sighting, Observation, Fleet, Rule modelleri
    │   ├── Catalog/SignatureEngine.swift # 252+ Filo için imza eşleştirme motoru
    │   ├── Decoders/AdvPayloadDecoder.swift # Apple TLV, FindMy, FastPair, OpenDroneID
    │   ├── Radio/BleScanner.swift   # CoreBluetooth gerçek zamanlı tarayıcı
    │   ├── Radio/WifiScanner.swift  # Çift modlu Wi-Fi gözlemcisi (App Store + MobileWiFi)
    │   ├── Tracking/CoTravelEngine.swift # "Moving with you" takipçi/ajan tespit algoritması
    │   ├── Tactical/TakPublisher.swift # Cursor-on-Target (CoT) UDP/ATAK yayıncısı
    │   └── ViewModels/FieldwatchViewModel.swift # Merkezi SwiftUI State koordinatörü
    ├── FieldwatchUI/Views/          # Taktiksel SwiftUI Arayüzü
    │   ├── RadarView.swift          # Askeri HUD stili döner radarlı tarama ekranı
    │   ├── LiveListView.swift       # Sparkline ve RSSI sinyal çubuklu canlı akış
    │   ├── DeviceDetailView.swift   # TLV ayrıştırıcı, paket dökümü ve bilgi kartı
    │   ├── HuntView.swift           # "Geiger sayacı" benzeri yakınlık avlama modu
    │   ├── FleetsView.swift         # 250+ Filo ve imza kuralı yöneticisi
    │   ├── SettingsView.swift       # TAK sunucu ayarları, tarama yoğunluğu, SITREP
    │   └── MainContentView.swift   # Ana sekme ve HUD gezinme ekranı
    └── FieldwatchApp/
        └── FieldwatchApp.swift      # @main SwiftUI uygulama giriş noktası
```

---

## 🚀 Xcode'da Çalıştırma ve Kurulum

1. **Projeyi Açma**:
   - macOS üzerinde Xcode'u açın.
   - `File > Open` seçeneğiyle `Fieldwatch-iOS/Package.swift` dosyasını açın veya mevcut bir iOS projesine **Local Swift Package** olarak ekleyin.
2. **Hedef Cihaz**:
   - Bluetooth LE donanımını tarayabilmek için gerçek bir iPhone/iPad seçin (iOS Simülatöründe BLE taraması donanımsal olarak desteklenmez).
3. **İmzalama (Signing & Capabilities)**:
   - Xcode'da projenizin `Signing & Capabilities` sekmesinden Apple Developer hesabınızı seçin.
   - `Access WiFi Information` yeteneğini ekleyin (Bağlı Wi-Fi BSSID bilgisi için).
4. **Çalıştırma**:
   - `Cmd + R` ile cihazınızda derleyip başlatın.

---

## 🛰️ Önemli Özellikler

1. **Taktik Radar (Radar HUD)**:
   - Dönen tarama çizgisi ve sinyal gücüne göre (merkeze yakın = güçlü) konumlandırılan hedefler.
   - Şüpheli/eş-seyahat eden hedefler kırmızı ve uyarı halkalarıyla vurgulanır.
2. **Gelişmiş BLE Protokol Çözücü (AdvPayloadDecoder)**:
   - **Apple Continuity**: AirDrop (0x05), AirPods / Beats pil ve model bilgisi (0x07), Hey Siri (0x08), AirPlay (0x09), Find My / AirTag (0x12).
   - **Google Fast Pair**: Model ID ve yakınlık eşleşmesi (0xFE2C).
   - **Eddystone**: UID, URL ve telemetri (voltaj, sıcaklık) (0xFEAA).
   - **OpenDroneID**: FAA/EASA uyumlu İHA/Drone kimliği ve GPS koordinatları (0xFFFA).
   - **Flipper Zero**: Güvenlik ve hacking araçları tespiti.
3. **Co-Travel / Tail Detection ("Moving with you")**:
   - Kullanıcının GPS rotasını ve çevredeki sinyalleri izleyerek sizinle birlikte hareket eden yabancı AirTag veya takip cihazlarını anında yakalar ve kırmızı alarm verir.
4. **Proximity Hunt Modu**:
   - Seçilen bir hedefe doğru yaklaştıkça artan dokunsal (haptic) geri bildirim ve görsel mesafe ölçeği.
5. **ATAK / iTAK (Cursor on Target) Entegrasyonu**:
   - Tespit edilen sinyalleri yerel ağdaki ATAK/iTAK/WinTAK haritalarına gerçek zamanlı CoT XML olarak gönderir.
