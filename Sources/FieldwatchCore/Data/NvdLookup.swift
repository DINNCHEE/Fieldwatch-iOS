//
//  NvdLookup.swift
//  Fieldwatch
//
//  NIST NVD firmware CVE lookup by vendor/model. No key needed for
//  light use (5 req/30sn); display name matched to CPE dictionary.
//

import Foundation

public struct NvdVuln: Sendable, Identifiable {
    public var id: String { cveId }
    public let cveId: String
    public let summary: String
    public let cvss: Double?
}

public struct NvdLookup: Sendable {
    private struct CpeResponse: Decodable {
        var products: [CpeProduct]?
        struct CpeProduct: Decodable {
            var cpe: CpeName?
            struct CpeName: Decodable {
                var cpeName: String?
            }
        }
    }

    private struct CveResponse: Decodable {
        var totalResults: Int?
        var vulnerabilities: [CveEntry]?
        struct CveEntry: Decodable {
            var cve: CveDetail?
            struct CveDetail: Decodable {
                var id: String?
                var descriptions: [CveDesc]?
                var metrics: CveMetrics?
                struct CveDesc: Decodable {
                    var lang: String?
                    var value: String?
                }
                struct CveMetrics: Decodable {
                    var cvssMetricV31: [Cvss]?
                    var cvssMetricV30: [Cvss]?
                    struct Cvss: Decodable {
                        var cvssData: CvssData?
                        struct CvssData: Decodable {
                            var baseScore: Double?
                        }
                    }
                }
            }
        }
    }

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("Fieldwatch-iOS/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Returns CVEs for a vendor/model string, or nil on any failure.
    public static func search(model: String) async -> [NvdVuln]? {
        guard var parts = URLComponents(string: "https://services.nvd.nist.gov/rest/json/cpes/2.0") else { return nil }
        parts.queryItems = [URLQueryItem(name: "keywordSearch", value: model),
                            URLQueryItem(name: "resultsPerPage", value: "10")]
        guard let url = parts.url,
              let data = await get(url),
              let decoded = try? JSONDecoder().decode(CpeResponse.self, from: data),
              let products = decoded.products,
              let firstProduct = products.first,
              let cpeName = firstProduct.cpe?.cpeName else { return nil }
        guard var cveParts = URLComponents(string: "https://services.nvd.nist.gov/rest/json/cves/2.0") else { return nil }
        cveParts.queryItems = [URLQueryItem(name: "cpeName", value: cpeName),
                               URLQueryItem(name: "resultsPerPage", value: "20")]
        guard let cveURL = cveParts.url,
              let cveData = await get(cveURL),
              let cves = try? JSONDecoder().decode(CveResponse.self, from: cveData) else { return nil }
        return (cves.vulnerabilities ?? []).compactMap { entry -> NvdVuln? in
            guard let detail = entry.cve, let id = detail.id else { return nil }
            let summary = detail.descriptions?.first(where: { $0.lang == "en" })?.value
                ?? detail.descriptions?.first?.value ?? ""
            var score: Double?
            if let arr = detail.metrics?.cvssMetricV31, let first = arr.first {
                score = first.cvssData?.baseScore
            }
            if score == nil,
               let arr = detail.metrics?.cvssMetricV30, let first = arr.first {
                score = first.cvssData?.baseScore
            }
            return NvdVuln(cveId: id, summary: summary, cvss: score)
        }
    }
}
