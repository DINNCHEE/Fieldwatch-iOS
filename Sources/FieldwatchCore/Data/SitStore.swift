//
//  SitStore.swift
//  Fieldwatch
//
//  Named observation sessions (sits): start/stop, persist, export.
//

import Foundation

public struct TrailPoint: Codable, Sendable {
    public var lat: Double
    public var lon: Double
    public var alt: Double
    public var at: Date

    public init(lat: Double, lon: Double, alt: Double = 0, at: Date = Date()) {
        self.lat = lat; self.lon = lon; self.alt = alt; self.at = at
    }
}

public struct SitSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var deviceCount: Int
    public var topDevices: [String]
    public var notes: String?
    public var path: [TrailPoint] = []

    public init(id: UUID = UUID(), name: String, startedAt: Date = Date(),
                endedAt: Date? = nil, deviceCount: Int = 0,
                topDevices: [String] = [], notes: String? = nil,
                path: [TrailPoint] = []) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.deviceCount = deviceCount
        self.topDevices = topDevices
        self.notes = notes
        self.path = path
    }

    public var durationText: String {
        let end = endedAt ?? Date()
        let secs = max(0, Int(end.timeIntervalSince(startedAt)))
        if secs < 60 { return "\(secs) sn" }
        if secs < 3600 { return "\(secs / 60) dk" }
        return "\(secs / 3600) sa \(secs % 3600 / 60) dk"
    }
}

public final class SitStore: @unchecked Sendable {
    public static let shared = SitStore()
    private let lock = NSLock()
    private init() {}

    private var dirURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sits", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func all() -> [SitSession] {
        lock.lock(); defer { lock.unlock() }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil) else { return [] }
        var out: [SitSession] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let sit = try? JSONDecoder().decode(SitSession.self, from: data) {
                out.append(sit)
            }
        }
        return out.sorted { $0.startedAt > $1.startedAt }
    }

    public func save(_ sit: SitSession) {
        lock.lock(); defer { lock.unlock() }
        let url = dirURL.appendingPathComponent("\(sit.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(sit) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func delete(_ sit: SitSession) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(
            at: dirURL.appendingPathComponent("\(sit.id.uuidString).json"))
    }

    public func exportJSON(_ sit: SitSession) -> String {
        guard let data = try? JSONEncoder().encode(sit),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
