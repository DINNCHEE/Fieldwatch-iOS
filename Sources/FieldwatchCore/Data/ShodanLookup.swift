//
//  ShodanLookup.swift
//  Fieldwatch
//
//  Internet-side view of YOUR OWN public IP (Shodan InternetDB, keyless).
//

import Foundation

public struct ShodanHost: Sendable {
    public var ip: String
    public var ports: [Int]
    public var hostnames: [String]
    public var vulns: [String]
    public var cpes: [String]
}

public struct ShodanLookup: Sendable {
    private struct InternetDb: Decodable {
        var ip: String?
        var ports: [Int]?
        var hostnames: [String]?
        var vulns: [String]?
        var cpes: [String]?
    }

    public static func publicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty else { return nil }
            return ip
        } catch {
            return nil
        }
    }

    public static func lookup(ip: String) async -> ShodanHost? {
        guard let url = URL(string: "https://internetdb.shodan.io/\(ip)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(InternetDb.self, from: data) else { return nil }
            return ShodanHost(ip: decoded.ip ?? ip,
                              ports: decoded.ports ?? [],
                              hostnames: decoded.hostnames ?? [],
                              vulns: decoded.vulns ?? [],
                              cpes: decoded.cpes ?? [])
        } catch {
            return nil
        }
    }
}
