//
//  WigleLookup.swift
//  Fieldwatch
//
//  On-demand Wigle (wigle.net) lookup for unknown Wi-Fi networks.
//  BYOK model: the user enters their OWN free API Name/Token
//  (wigle.net/account), stored in Keychain. No shared key, no bulk
//  harvest, transient display only. Data © WiGLE.net.
//

import Foundation

public struct WigleResult: Sendable {
    public let ssid: String
    public let bssid: String
    public let latitude: Double?
    public let longitude: Double?
    public let encryption: String?
    public let channel: Int?
    public let city: String?
    public let region: String?
    public let country: String?
    public let firstSeen: String?
    public let lastSeen: String?

    public var coordinateText: String? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return String(format: "%.5f, %.5f", lat, lon)
    }
}

public enum WigleError: Error, Sendable {
    case noCredentials
    case rateLimited
    case notFound
    case network(String)
    case decoding
}

public struct WigleLookup: Sendable {
    static let nameAccount = "wigle-api-name"
    static let tokenAccount = "wigle-api-token"

    public static var hasCredentials: Bool {
        Keychain.load(account: nameAccount) != nil &&
        Keychain.load(account: tokenAccount) != nil
    }

    public static func saveCredentials(name: String, token: String) -> Bool {
        Keychain.save(account: nameAccount, value: name) &&
        Keychain.save(account: tokenAccount, value: token)
    }

    public static func clearCredentials() {
        Keychain.delete(account: nameAccount)
        Keychain.delete(account: tokenAccount)
    }

    private struct SearchResponse: Decodable {
        var success: Bool
        var totalResults: Int
        var results: [Item]?
        struct Item: Decodable {
            var ssid: String?
            var netid: String?
            var trilat: Double?
            var trilong: Double?
            var encryption: String?
            var channel: Int?
            var city: String?
            var region: String?
            var country: String?
            var firsttime: String?
            var lasttime: String?
        }
    }

    /// Look up one BSSID. Throws WigleError. Respects 429 rate limits.
    public static func search(bssid: String) async throws -> WigleResult {
        guard let apiName = Keychain.load(account: nameAccount),
              let apiToken = Keychain.load(account: tokenAccount),
              !apiName.isEmpty, !apiToken.isEmpty else {
            throw WigleError.noCredentials
        }
        var parts = URLComponents(string: "https://api.wigle.net/api/v2/network/search")
        parts?.queryItems = [URLQueryItem(name: "netid", value: bssid)]
        guard let url = parts?.url else { throw WigleError.network("bad url") }
        let credentials = "\(apiName):\(apiToken)".data(using: .utf8)!.base64EncodedString()
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("Fieldwatch-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WigleError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw WigleError.rateLimited
        }
        guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
              decoded.success else { throw WigleError.decoding }
        guard let item = decoded.results?.first else { throw WigleError.notFound }
        return WigleResult(
            ssid: item.ssid ?? "", bssid: item.netid ?? bssid,
            latitude: item.trilat, longitude: item.trilong,
            encryption: item.encryption, channel: item.channel,
            city: item.city, region: item.region, country: item.country,
            firstSeen: item.firsttime, lastSeen: item.lasttime
        )
    }
}
