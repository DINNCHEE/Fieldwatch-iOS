//
//  CoTravelEngine.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import Foundation
import CoreLocation

public final class CoTravelEngine: Sendable {
    public static let shared = CoTravelEngine()
    
    // Minimum distance traversed together to qualify as co-traveling (meters)
    private let minDistanceMeters: Double = 150.0
    // Minimum duration observed across movements (seconds)
    private let minTimeSpanSeconds: TimeInterval = 180.0
    
    public init() {}
    
    public func evaluateCoTraveling(
        firstSeen: Date,
        lastSeen: Date,
        locationHistory: [CLLocationCoordinate2D]
    ) -> Bool {
        guard locationHistory.count >= 2 else { return false }
        
        let timeSpan = lastSeen.timeIntervalSince(firstSeen)
        guard timeSpan >= minTimeSpanSeconds else { return false }
        
        guard let firstLoc = locationHistory.first, let lastLoc = locationHistory.last else { return false }
        
        let start = CLLocation(latitude: firstLoc.latitude, longitude: firstLoc.longitude)
        let end = CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude)
        
        let directDistance = start.distance(from: end)
        
        // If distance between first observation point and latest observation point is significant
        if directDistance >= minDistanceMeters {
            return true
        }
        
        // Also check maximum span between any two points in the history
        var maxSpan: Double = 0
        for i in 0..<locationHistory.count {
            let locA = CLLocation(latitude: locationHistory[i].latitude, longitude: locationHistory[i].longitude)
            for j in (i + 1)..<locationHistory.count {
                let locB = CLLocation(latitude: locationHistory[j].latitude, longitude: locationHistory[j].longitude)
                let dist = locA.distance(from: locB)
                if dist > maxSpan {
                    maxSpan = dist
                    if maxSpan >= minDistanceMeters {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}
