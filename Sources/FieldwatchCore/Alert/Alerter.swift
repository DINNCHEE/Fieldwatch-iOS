//
//  Alerter.swift
//  Fieldwatch
//
//  Watchlist alerts: beep + voice + notification. Toggles live in
//  UserDefaults so Settings and the engine always agree.
//

import Foundation
import AudioToolbox
import AVFoundation
import UserNotifications

public struct Alerter: Sendable {
    private static let beepKey = "fw_alert_beep"
    private static let voiceKey = "fw_alert_voice"
    private static let notifyKey = "fw_alert_notify"

    public static var beepEnabled: Bool {
        UserDefaults.standard.object(forKey: beepKey) as? Bool ?? true
    }
    public static var voiceEnabled: Bool {
        UserDefaults.standard.object(forKey: voiceKey) as? Bool ?? false
    }
    public static var notifyEnabled: Bool {
        UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true
    }

    public static func setBeep(_ v: Bool) { UserDefaults.standard.set(v, forKey: beepKey) }
    public static func setVoice(_ v: Bool) { UserDefaults.standard.set(v, forKey: voiceKey) }
    public static func setNotify(_ v: Bool) { UserDefaults.standard.set(v, forKey: notifyKey) }

    private static let speaker = AVSpeechSynthesizer()

    public static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func test() {
        beep()
        speak("Fieldwatch uyarı testi")
        notify(title: "Fieldwatch test", body: "Uyarılar çalışıyor.")
    }

    public static func coTravel(_ sighting: Sighting) {
        beep()
        speak("Takip uyarısı: \(sighting.displayName) sizinle birlikte hareket ediyor.")
        notify(title: "Sizinle hareket eden cihaz", body: sighting.displayName)
    }

    public static func watched(_ sighting: Sighting) {
        beep()
        let name = sighting.displayName
        speak("İzlenen cihaz görüldü: \(name)")
        notify(title: "İzlenen cihaz", body: name)
    }

    /// Short geiger tick for Hunt mode.
    public static func tick() {
        guard beepEnabled else { return }
        AudioServicesPlaySystemSound(1057)
    }

    public static func beep() {
        guard beepEnabled else { return }
        AudioServicesPlaySystemSound(1005)
    }

    public static func speak(_ text: String) {
        guard voiceEnabled else { return }
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        speaker.speak(utterance)
    }

    public static func notify(title: String, body: String) {
        guard notifyEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
