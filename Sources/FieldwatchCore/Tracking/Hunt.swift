//
//  Hunt.swift
//  Fieldwatch
//
//  Relative-loudness hunt brain. 1:1 port of the original Hunt:
//  RSSI is not distance and not a bearing.
//

import Foundation

public enum HuntCue: String, Sendable {
    case veryClose = "Very Close"
    case closer = "Closer"
    case further = "Further"
    case same = "About the same"
    case waiting = "Listening…"
    case quiet = "Quiet"
    case gone = "Gone"

    public var hint: String {
        switch self {
        case .veryClose: return "Screaming loud here. Look around — usually in-hand, pocket, or the same bag. Not meters."
        case .closer: return "Louder than a few seconds ago. Keep walking that way."
        case .further: return "Quieter than a few seconds ago. Turn or back up."
        case .same: return "No clear change yet. Slow down; hold the phone still."
        case .waiting: return "Need a few seconds of packets to compare."
        case .quiet: return "No packet for a few seconds. Silent, or behind a wall."
        case .gone: return "Left the live set. Randomized BLE often vanishes mid-hunt."
        }
    }
}

public struct RssiSample: Sendable, Hashable {
    public let rssi: Int
    public let at: Date
    public init(rssi: Int, at: Date = Date()) {
        self.rssi = rssi; self.at = at
    }
}

public struct Hunt: Sendable {
    static let recentSec: TimeInterval = 2.0
    static let earlierFromSec: TimeInterval = 8.0
    static let earlierToSec: TimeInterval = 3.5
    static let stepDb: Double = 3.0
    static let quietSec: TimeInterval = 8.0
    static let veryCloseDbm: Double = -45.0
    static let tickLoudDbm = -40
    static let tickQuietDbm = -90
    static let tickFastSec: TimeInterval = 0.09
    static let tickSlowSec: TimeInterval = 1.4

    public static func cue(samples: [RssiSample], now: Date = Date(),
                           lastSeen: Date?, missing: Bool) -> HuntCue {
        if missing { return .gone }
        guard let lastSeen = lastSeen else { return .waiting }
        if now.timeIntervalSince(lastSeen) > quietSec { return .quiet }
        let usable = samples.filter { (-127...126).contains($0.rssi) }
        let recent = usable.filter { $0.at >= now.addingTimeInterval(-recentSec) }
        let loud: Double?
        if !recent.isEmpty {
            loud = recent.map { Double($0.rssi) }.reduce(0, +) / Double(recent.count)
        } else {
            loud = usable.last(where: { now.timeIntervalSince($0.at) <= quietSec }).map { Double($0.rssi) }
        }
        if let loud = loud, loud >= veryCloseDbm { return .veryClose }
        let earlier = usable.filter {
            let age = now.timeIntervalSince($0.at)
            return age >= earlierToSec && age <= earlierFromSec
        }
        if recent.count < 2 || earlier.count < 2 { return .waiting }
        let recentAvg = recent.map { Double($0.rssi) }.reduce(0, +) / Double(recent.count)
        let earlierAvg = earlier.map { Double($0.rssi) }.reduce(0, +) / Double(earlier.count)
        let delta = recentAvg - earlierAvg
        if delta >= stepDb { return .closer }
        if delta <= -stepDb { return .further }
        return .same
    }

    /// Seconds between geiger ticks, or nil to stay silent.
    public static func tickInterval(rssi: Int?, cue: HuntCue) -> TimeInterval? {
        if cue == .quiet || cue == .gone { return nil }
        guard let r = rssi else { return nil }
        let span = Double(tickLoudDbm - tickQuietDbm)
        let t = min(1.0, max(0.0, Double(r - tickQuietDbm) / span))
        return tickSlowSec + (tickFastSec - tickSlowSec) * t
    }
}
