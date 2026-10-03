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
}
