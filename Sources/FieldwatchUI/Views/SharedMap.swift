//
//  SharedMap.swift
//  Fieldwatch
//
//  Small MapKit wrapper (iOS 16 compatible): trail polyline + points.
//

import SwiftUI
import MapKit
import CoreLocation
#if SWIFT_PACKAGE
import FieldwatchCore
#endif

public struct MapPoint: Identifiable {
    public var id: String
    public var coordinate: CLLocationCoordinate2D
    public var title: String?
    public init(id: String = UUID().uuidString, coordinate: CLLocationCoordinate2D, title: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
    }
}

public struct SharedMap: UIViewRepresentable {
    var trail: [CLLocationCoordinate2D]
    var points: [MapPoint]

    public init(trail: [CLLocationCoordinate2D] = [], points: [MapPoint] = []) {
        self.trail = trail
        self.points = points
    }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        if trail.count > 1 {
            map.addOverlay(MKPolyline(coordinates: trail, count: trail.count))
        }
        for p in points {
            let annotation = MKPointAnnotation()
            annotation.coordinate = p.coordinate
            annotation.title = p.title
            map.addAnnotation(annotation)
        }
        var coords = trail
        coords += points.map { $0.coordinate }
        guard !coords.isEmpty else { return }
        var rect = MKMapRect.null
        for c in coords {
            let point = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: point.x - 500, y: point.y - 500, width: 1000, height: 1000))
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public class Coordinator: NSObject, MKMapViewDelegate {
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
