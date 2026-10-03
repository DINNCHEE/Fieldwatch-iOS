//
//  CoTravelEngine.swift
//  Fieldwatch
//
//  "Moving with you" detection. BLE tags only: 3 gates (time span,
//  distinct places, distance). Wi-Fi APs never count — every drive-past
//  AP would false-positive otherwise.
//

import Foundation
import CoreLocation

public final class CoTravelEngine: Sendable {
    public static let shared = CoTravelEngine()

    // A tag must be seen across this long to count (seconds).
    private let minTimeSpanSeconds: TimeInterval = 8 * 60
    // Distinct ~100 m grid cells required.
    private let minCells = 2
    // Furthest two fixes must be this far apart (meters).
    private let minDistanceMeters: Double = 45.0
    // Minimum GPS fixes to judge.
    private let minFixes = 3

    public init() {}

    /// Tag-style evaluation for one sighting. Wi-Fi always returns false.
    public func evaluateTag(_ sighting: Sighting) -> Bool {
        guard sighting.kind == .ble else { return false }
        let history = sighting.locationHistory
        guard history.count >= minFixes else { return false }
        let timeSpan = sighting.lastSeen.timeIntervalSince(sighting.firstSeen)
        guard timeSpan >= minTimeSpanSeconds else { return false }

        var cells = Set<String>()
        var maxSpan: Double = 0
        let points = history.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        for loc in history {
            // ~100 m grid cells (0.001° latitude ≈ 111 m).
            let cell = "\(Int((loc.latitude * 1000).rounded())):\(Int((loc.longitude * 1000).rounded()))"
            cells.insert(cell)
        }
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dist = points[i].distance(from: points[j])
                if dist > maxSpan { maxSpan = dist }
            }
        }
        return cells.count >= minCells && maxSpan >= minDistanceMeters
    }

    /// Legacy entry kept for compatibility; delegates to tag logic.
    public func evaluateCoTraveling(
        firstSeen: Date,
        lastSeen: Date,
        locationHistory: [CLLocationCoordinate2D]
    ) -> Bool {
        guard locationHistory.count >= minFixes else { return false }
        let timeSpan = lastSeen.timeIntervalSince(firstSeen)
        guard timeSpan >= minTimeSpanSeconds else { return false }
        guard let firstLoc = locationHistory.first, let lastLoc = locationHistory.last else { return false }
        let start = CLLocation(latitude: firstLoc.latitude, longitude: firstLoc.longitude)
        let end = CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude)
        return start.distance(from: end) >= minDistanceMeters
    }
}
