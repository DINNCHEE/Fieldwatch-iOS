//
//  UltrasonicView.swift
//  Fieldwatch
//
//  Near-ultrasound tracking-beacon detector (18-20 kHz).
//  Microphone + Goertzel tones. Foreground only.
//

import SwiftUI
import AVFoundation
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

final class UltrasonicScanner: NSObject, ObservableObject {
    @Published var level: Double = 0
    @Published var detecting: Bool = false
    @Published var stateText: String = "hazır"

    private var engine: AVAudioEngine?
    private var streak = 0
    private let targets: [Float] = [18000, 18500, 19000, 19500, 20000]

    private func goertzel(_ x: [Float], target: Float, fs: Float) -> Double {
        let n = x.count
        guard n > 0 else { return 0 }
        let k = 0.5 + (Float(n) * target / fs)
        let w = 2.0 * Double.pi * Double(k) / Double(n)
        let coeff = 2.0 * cos(w)
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for v in x {
            s0 = Double(v) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }

    func start() {
        stop()
        stateText = "mikrofon izni bekleniyor…"
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.stateText = "Mikrofon izni verilmedi."
                    return
                }
                do {
                    let engine = AVAudioEngine()
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate >= 40000 else {
                        self.stateText = "Örnekleme hızı yetersiz."
                        return
                    }
                    let fs = Float(format.sampleRate)
                    input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                        guard let self = self,
                              let ptr = buffer.floatChannelData?[0] else { return }
                        let frames = Int(buffer.frameLength)
                        guard frames >= 2048 else { return }
                        let arr = Array(UnsafeBufferPointer(start: ptr, count: frames))
                        self.process(arr, fs: fs)
                    }
                    engine.prepare()
                    try engine.start()
                    self.engine = engine
                    self.stateText = "dinleniyor (18-20 kHz)…"
                } catch {
                    self.stateText = "Başlatılamadı."
                }
            }
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        streak = 0
        detecting = false
        level = 0
    }

    private func process(_ x: [Float], fs: Float) {
        let powers = targets.map { goertzel(x, target: $0, fs: fs) }
        guard let top = powers.max(), top > 0 else { return }
        let sorted = powers.sorted(by: >)
        let second = sorted.count > 1 ? sorted[1] : 0
        // Tone present if one bin dominates + above absolute floor.
        let total = x.reduce(0) { $0 + Double($1 * $1) } / Double(x.count)
        let ratio = top / max(total * Double(x.count) * 0.02, 1e-9)
        let hit = top > second * 8 && ratio > 1.0
        let lvl = min(1.0, ratio / 8.0)
        DispatchQueue.main.async {
            self.level = lvl
            if hit {
                self.streak += 1
                if self.streak >= 30 {
                    self.detecting = true
                }
            } else {
                self.streak = 0
                self.detecting = false
            }
        }
    }
}

public struct UltrasonicView: View {
    @StateObject private var scanner = UltrasonicScanner()
    @State private var running = false

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Mağaza takip sesleri (18-20 kHz) mikrofonla aranır. Pil tüketir; sessiz odada daha sağlıklı.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 180, height: 180)
                Circle()
                    .trim(from: 0, to: CGFloat(scanner.level))
                    .stroke(scanner.detecting ? Color.red : Color.green,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text(scanner.detecting ? "SİNYAL" : "temiz")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundColor(scanner.detecting ? .red : .green)
                    Text("18-20 kHz")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            Text(scanner.stateText)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(running ? "Durdur" : "Dinlemeye Başla") {
                if running {
                    scanner.stop()
                    running = false
                } else {
                    scanner.start()
                    running = true
                }
            }
            .fontWeight(.bold)

            Spacer()
        }
        .padding()
        .navigationTitle("Ultrasonik Tarama")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            scanner.stop()
        }
    }
}
