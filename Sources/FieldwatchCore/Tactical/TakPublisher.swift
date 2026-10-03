//
//  TakPublisher.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import Network
import CoreLocation

public final class TakPublisher: @unchecked Sendable {
    public static let shared = TakPublisher()
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "app.fieldwatch.tak", qos: .utility)
    
    public var targetHost: String = "239.2.3.1" // Default ATAK Multicast
    public var targetPort: UInt16 = 6969
    public var isEnabled: Bool = false
    
    public init() {}
    
    public func configure(host: String, port: UInt16, enabled: Bool) {
        queue.async {
            self.targetHost = host
            self.targetPort = port
            self.isEnabled = enabled
            self.setupConnection()
        }
    }
    
    private func setupConnection() {
        connection?.cancel()
        guard isEnabled else { return }
        
        let endpointHost = NWEndpoint.Host(targetHost)
        guard let endpointPort = NWEndpoint.Port(rawValue: targetPort) else { return }
        
        let params = NWParameters.udp
        if targetHost.hasPrefix("239.") || targetHost.hasPrefix("224.") {
            params.allowLocalEndpointReuse = true
        }
        
        let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("TakPublisher: Connected to \(self.targetHost):\(self.targetPort)")
            case .failed(let error):
                print("TakPublisher: Failed to connect: \(error)")
            default:
                break
            }
        }
        conn.start(queue: queue)
        self.connection = conn
    }
    
    public func publish(sighting: Sighting) {
        guard isEnabled, let loc = sighting.location else { return }
        queue.async {
            let cotXml = self.buildCotXml(sighting: sighting, location: loc)
            guard let data = cotXml.data(using: .utf8) else { return }
            
            self.connection?.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    print("TakPublisher: Send error: \(error)")
                }
            }))
        }
    }
    
    private func buildCotXml(sighting: Sighting, location: CLLocationCoordinate2D) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let now = Date()
        let timeStr = isoFormatter.string(from: now)
        let staleDate = now.addingTimeInterval(120) // 2 minutes stale
        let staleStr = isoFormatter.string(from: staleDate)
        
        let uid = "Fieldwatch.\(sighting.kind.rawValue).\(sighting.identifier.replacingOccurrences(of: ":", with: ""))"
        let callsign = sighting.name ?? sighting.fleetName ?? "\(sighting.kind.rawValue) \(sighting.identifier.prefix(8))"
        let cotType = sighting.isCoTraveling ? "a-u-G-U-C-I" : "a-f-G-E-V-R" // Unknown / Neutral RF sensor
        
        let remarks = "Fieldwatch Detection: \(sighting.kind.rawValue) [\(sighting.identifier)] RSSI: \(sighting.lastRssi) dBm. Fleet: \(sighting.fleetName ?? "None"). Hints: \(sighting.roleHints.first?.label ?? "None")"
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <event version="2.0" uid="\(uid)" type="\(cotType)" time="\(timeStr)" start="\(timeStr)" stale="\(staleStr)" how="m-g">
            <point lat="\(location.latitude)" lon="\(location.longitude)" hae="0.0" ce="20.0" le="9999999.0"/>
            <detail>
                <contact callsign="\(callsign)"/>
                <remarks>\(remarks)</remarks>
            </detail>
        </event>
        """
    }
}
