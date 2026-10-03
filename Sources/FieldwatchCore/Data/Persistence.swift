//
//  Persistence.swift
//  Fieldwatch
//
//  Local persistence: fleet toggles, custom names/notes/bookmarks,
//  settings. Everything the stock app must not forget on restart.
//

import Foundation

public struct CustomDevice: Codable, Sendable {
    public var id: String
    public var customName: String?
    public var notes: String?
    public var bookmarked: Bool
    public var alertEnabled: Bool

    public init(id: String, customName: String? = nil, notes: String? = nil,
                bookmarked: Bool = false, alertEnabled: Bool = false) {
        self.id = id
        self.customName = customName
        self.notes = notes
        self.bookmarked = bookmarked
        self.alertEnabled = alertEnabled
    }
}

private struct PersistedState: Codable {
    var fleets: [String: Bool] = [:]
    var customs: [String: CustomDevice] = [:]
    var customFleets: [Fleet]?
}

public final class Persistence: @unchecked Sendable {
    public static let shared = Persistence()

    private let lock = NSLock()
    private var state = PersistedState()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fieldwatch-state.json")
    }

    private init() { load() }

    public func load() {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        state = parsed
    }

    public func save() {
        lock.lock()
        let snapshot = state
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Fleets
    public func fleetEnabled(id: String, default defaultValue: Bool = true) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.fleets[id] ?? defaultValue
    }

    public func hasFleet(id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.fleets[id] != nil
    }

    public func setFleet(id: String, enabled: Bool) {
        lock.lock(); state.fleets[id] = enabled; lock.unlock()
        save()
    }

    // MARK: - Custom devices
    public func custom(id: String) -> CustomDevice? {
        lock.lock(); defer { lock.unlock() }
        return state.customs[id]
    }

    public func setCustom(_ device: CustomDevice) {
        lock.lock(); state.customs[device.id] = device; lock.unlock()
        save()
    }

    public func removeCustom(id: String) {
        lock.lock(); state.customs.removeValue(forKey: id); lock.unlock()
        save()
    }

    public func allCustoms() -> [CustomDevice] {
        lock.lock(); defer { lock.unlock() }
        return Array(state.customs.values)
    }

    // MARK: - Custom fleets + iCloud mirror
    public func customFleetList() -> [Fleet] {
        lock.lock(); defer { lock.unlock() }
        return state.customFleets ?? []
    }

    public func saveCustomFleets(_ fleets: [Fleet]) {
        lock.lock(); state.customFleets = fleets; lock.unlock()
        save()
    }

    private static let iCloudFleetsKey = "fw_fleets_json"

    /// Mirror fleet toggles to iCloud key-value store (best effort).
    public func pushFleetsToCloud() {
        lock.lock()
        guard let data = try? JSONEncoder().encode(state.fleets),
              let str = String(data: data, encoding: .utf8) else {
            lock.unlock()
            return
        }
        lock.unlock()
        NSUbiquitousKeyValueStore.default.set(str, forKey: Self.iCloudFleetsKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Adopt iCloud fleet toggles when local has none saved.
    public func pullFleetsFromCloudIfEmpty() {
        lock.lock()
        let empty = state.fleets.isEmpty
        lock.unlock()
        guard empty,
              let str = NSUbiquitousKeyValueStore.default.string(forKey: Self.iCloudFleetsKey),
              let data = str.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data),
              !map.isEmpty else { return }
        lock.lock()
        if state.fleets.isEmpty { state.fleets = map }
        lock.unlock()
        save()
    }
}
