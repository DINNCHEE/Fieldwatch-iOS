//
//  CatalogUpdate.swift
//  Fieldwatch
//
//  In-app stock signature update from the upstream GitHub dist.
//  Keeps the user's fleet on/off choices.
//

import Foundation

public struct CatalogUpdate: Sendable {
    static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/OffGridPete/Fieldwatch/main/dist/fieldwatch-signatures-v2.json")!

    public static func checkAndApply() async -> String {
        let current = SignatureEngine.shared.catalogVersion
        let data: Data
        do {
            var request = URLRequest(url: catalogURL, timeoutInterval: 30)
            request.setValue("Fieldwatch-iOS/1.0", forHTTPHeaderField: "User-Agent")
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            return "İndirme hatası: \(error.localizedDescription)"
        }
        guard let parsed = try? JSONDecoder().decode(FleetCatalog.self, from: data) else {
            return "Dosya çözümlenemedi."
        }
        if parsed.catalogVersion <= current {
            return "Zaten güncel (v\(current))."
        }
        let old = current
        SignatureEngine.shared.replaceStock(fleets: parsed.fleets, version: parsed.catalogVersion)
        return "v\(old) → v\(parsed.catalogVersion) (\(parsed.fleets.count) filo)."
    }
}
