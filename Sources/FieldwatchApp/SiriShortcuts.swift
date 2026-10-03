//
//  SiriShortcuts.swift
//  Fieldwatch
//
//  App Shortcuts: "Tara" / "Taramayı durdur" (iOS 16+, no extra target).
//

import AppIntents
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

struct StartScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Taramayı Başlat"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BleScanner.shared.startScanning()
            WifiScanner.shared.startScanning()
        }
        return .result()
    }
}

struct StopScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Taramayı Durdur"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BleScanner.shared.stopScanning()
            WifiScanner.shared.stopScanning()
        }
        return .result()
    }
}

struct FieldwatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: ["\(.applicationName) ile tara", "Taramayı başlat"],
            shortTitle: "Tara",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: StopScanIntent(),
            phrases: ["Taramayı durdur"],
            shortTitle: "Durdur",
            systemImageName: "stop.circle"
        )
    }
}
