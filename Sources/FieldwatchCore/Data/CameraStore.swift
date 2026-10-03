//
//  CameraStore.swift
//  Fieldwatch
//
//  Own-camera credentials (Keychain) + working snapshot URL cache.
//

import Foundation

public struct CameraStore: Sendable {
    private static func userAccount(_ id: String) -> String { "cam-\(id)-user" }
    private static func passAccount(_ id: String) -> String { "cam-\(id)-pass" }
    private static func snapKey(_ id: String) -> String { "cam-snap-\(id)" }

    public static func credentials(id: String) -> (user: String, pass: String)? {
        guard let user = Keychain.load(account: userAccount(id)),
              let pass = Keychain.load(account: passAccount(id)),
              !user.isEmpty else { return nil }
        return (user, pass)
    }

    public static func saveCredentials(id: String, user: String, pass: String) {
        _ = Keychain.save(account: userAccount(id), value: user)
        _ = Keychain.save(account: passAccount(id), value: pass)
    }

    public static func clearCredentials(id: String) {
        Keychain.delete(account: userAccount(id))
        Keychain.delete(account: passAccount(id))
        UserDefaults.standard.removeObject(forKey: snapKey(id))
    }

    public static func snapshotURL(id: String) -> String? {
        UserDefaults.standard.string(forKey: snapKey(id))
    }

    public static func saveSnapshotURL(id: String, url: String) {
        UserDefaults.standard.set(url, forKey: snapKey(id))
    }

    public static func forgetSnapshotURL(id: String) {
        UserDefaults.standard.removeObject(forKey: snapKey(id))
    }
}
