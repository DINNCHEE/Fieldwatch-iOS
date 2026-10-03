//
//  WigleUpload.swift
//  Fieldwatch
//
//  Contribute real-MAC Wi-Fi observations to Wigle (BYOK credentials).
//  BLE CoreBluetooth UUIDs are NEVER uploaded (they are per-phone
//  randomized identifiers, not hardware addresses — uploading them
//  would pollute the database).
//

import Foundation

public struct WigleUpload: Sendable {
    static let uploadURL = URL(
        string: "https://api.wigle.net/api/v2/file/upload")!

    /// WigleWifi-1.6 CSV for Wi-Fi rows with real BSSIDs + GPS.
    public static func buildCSV(sightings: [Sighting]) -> String {
        var lines: [String] = [
            "WigleWifi-1.6,appRelease=1.0.4,model=iPhone,release=17.0,device=Fieldwatch-iOS,display=Fieldwatch,board=iOS,brand=Apple,star=Sol,body=3,subBody=0",
            "MAC,SSID,AuthMode,FirstSeen,Channel,Frequency,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,RCOIs,MfgrId,Type",
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        for s in sightings where s.kind == .wifi && isRealMac(s.identifier) {
            guard let loc = s.location else { continue }
            let ssid = (s.name ?? "").replacingOccurrences(of: ",", with: " ")
            let caps = "[WPA2][ESS]"
            let first = formatter.string(from: s.firstSeen)
            let ch = s.channel ?? 0
            let freq = ch == 0 ? 0 : (ch <= 14 ? 2412 + max(0, ch - 1) * 5 : 5000 + ch * 5)
            lines.append("\(s.identifier),\(ssid),\(caps),\(first),\(ch),\(freq),\(s.lastRssi),\(loc.latitude),\(loc.longitude),0,20,,,WIFI")
        }
        return lines.joined(separator: "\n")
    }

    /// Real hardware MAC? Skips IPs, UUIDs, randomized local BSSIDs.
    public static func isRealMac(_ id: String) -> Bool {
        let parts = id.split(separator: ":")
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 }) else { return false }
        let hex = id.filter { $0.isLetter || $0.isNumber }
        guard hex.count == 12, UInt64(hex, radix: 16) != nil else { return false }
        return !RadioDb.shared.isRandomized(id)
    }

    public enum UploadError: Error {
        case noCredentials
        case nothingToUpload
        case failed(String)
    }

    public static func upload(csv: String) async throws -> String {
        guard let apiName = Keychain.load(account: WigleLookup.nameAccount),
              let apiToken = Keychain.load(account: WigleLookup.tokenAccount),
              !apiName.isEmpty, !apiToken.isEmpty else {
            throw UploadError.noCredentials
        }
        let boundary = "FieldwatchBoundary\(UUID().uuidString.prefix(8))"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"fieldwatch.csv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csv.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let credentials = "\(apiName):\(apiToken)".data(using: .utf8)!.base64EncodedString()
        var request = URLRequest(url: uploadURL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UploadError.failed(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UploadError.failed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        struct Resp: Decodable {
            var success: Bool
            var warning: String?
        }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data),
              decoded.success else {
            throw UploadError.failed("sunucu kabul etmedi")
        }
        return decoded.warning?.isEmpty == false ? decoded.warning! : "Yüklendi ✓"
    }
}
