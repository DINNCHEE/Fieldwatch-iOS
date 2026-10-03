//
//  DnsAudit.swift
//  Fieldwatch
//
//  DNS hijack check: resolve a control hostname through the system
//  resolver (getaddrinfo) and through DNS-over-HTTPS, compare.
//

import Foundation

public struct DnsAuditResult: Sendable {
    public var systemIPs: [String]
    public var dohIPs: [String]
    public var match: Bool
    public var verdict: String
}

public struct DnsAudit: Sendable {
    static let controlHost = "www.example.com"

    public static func systemResolve(host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(result) }
        var ips: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let c = cursor {
            if let addrPtr = c.pointee.ai_addr {
                var addr = addrPtr.pointee
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                // IPv4 only (hints forced AF_INET).
                var sin = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                }
                if inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    ips.append(String(cString: buf))
                }
            }
            cursor = c.pointee.ai_next
        }
        return Array(Set(ips)).sorted()
    }

    private struct DohResponse: Decodable {
        var Answer: [DohAnswer]?
        struct DohAnswer: Decodable {
            var data: String?
            var type: Int?
        }
    }

    public static func dohResolve(host: String) async -> [String] {
        guard var parts = URLComponents(string: "https://dns.google/resolve") else { return [] }
        parts.queryItems = [URLQueryItem(name: "name", value: host),
                            URLQueryItem(name: "type", value: "A")]
        guard let url = parts.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = try? JSONDecoder().decode(DohResponse.self, from: data) else { return [] }
            let ips = (decoded.Answer ?? []).compactMap { a -> String? in
                guard a.type == 1, let d = a.data else { return nil }
                return d
            }
            return Array(Set(ips)).sorted()
        } catch {
            return []
        }
    }

    public static func audit() async -> DnsAuditResult {
        let sys = systemResolve(host: controlHost)
        let doh = await dohResolve(host: controlHost)
        let match: Bool
        let verdict: String
        if sys.isEmpty || doh.isEmpty {
            match = true
            verdict = "Karşılaştırma yapılamadı (bir taraf yanıt vermedi)."
        } else if Set(sys) == Set(doh) {
            match = true
            verdict = "Temiz: sistem DNS'i ile güvenli DNS aynı yanıtı veriyor."
        } else {
            match = false
            verdict = "ŞÜPHELİ: sistem DNS'i farklı IP dönüyor — DNS kaçırma olabilir."
        }
        return DnsAuditResult(systemIPs: sys, dohIPs: doh, match: match, verdict: verdict)
    }
}
