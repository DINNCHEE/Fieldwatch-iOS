//
//  OnboardingView.swift
//  Fieldwatch
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct OnboardingView: View {
    var onDone: () -> Void

    public init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    private let pages: [(icon: String, title: String, text: String)] = [
        ("antenna.radiowaves.left.and.right", "Hoş geldin",
         "Fieldwatch çevrendeki Bluetooth ve WiFi yayınlarını dinler, tanır ve kaydeder."),
        ("scope", "Tara ve Avla",
         "Tara ile gör, Süpürme ile oda oda gizli kamera ve takipçi ara, Hunt ile kaynağa yürü."),
        ("bell.fill", "Uyarılar",
         "Seninle hareket eden cihazda ve izlediğin cihaz görülünce bip + ses + bildirim alırsın."),
        ("lock.shield", "Gizlilik notu",
         "Tarama pasiftir; hiçbir cihaza bağlanmaz, sinyal bozmaz. iOS'un görmediği WiFi'lar için ESP32 Companion gerekir."),
    ]

    public var body: some View {
        TabView {
            ForEach(pages.indices, id: \.self) { idx in
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: pages[idx].icon)
                        .font(.system(size: 64))
                        .foregroundColor(.green)
                    Text(pages[idx].title)
                        .font(.title.bold())
                    Text(pages[idx].text)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                    if idx == pages.count - 1 {
                        Button("Başla") {
                            UserDefaults.standard.set(true, forKey: "fw_onboarded")
                            onDone()
                        }
                        .font(.headline)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    Spacer()
                }
                .tag(idx)
            }
        }
        .tabViewStyle(.page)
        .preferredColorScheme(.dark)
    }
}
