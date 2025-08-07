import SwiftUI
import MapKit

// MARK: - Enhanced Map View Container with Multi-Modal Route Support
struct EnhancedMapViewContainer: UIViewRepresentable {
    let locationManager: LocationManager
    let mapType: MKMapType
    let searchResults: [MKMapItem]
    let selectedPlace: MKMapItem?
    let carWalkRoute: CarWalkRouteResponse?
    @Binding var userTrackingMode: MKUserTrackingMode
    
    // Zoom level constants
    private let defaultZoomMeters: CLLocationDistance = 500
    private let selectedPlaceZoomMeters: CLLocationDistance = 300
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode
        mapView.mapType = mapType
        
        // Always start with Montreal region
        let montrealRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673),
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
        mapView.setRegion(montrealRegion, animated: false)
        
        // If we have user location, zoom to it
        if let location = locationManager.lastLocation {
            let userRegion = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: defaultZoomMeters,
                longitudinalMeters: defaultZoomMeters
            )
            mapView.setRegion(userRegion, animated: false)
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.mapType = mapType
        uiView.userTrackingMode = userTrackingMode

        // Remove existing annotations and overlays
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        uiView.removeOverlays(uiView.overlays)

        // Add search results
        for item in searchResults {
            let placemark = item.placemark
            let annotation = MKPointAnnotation()
            annotation.coordinate = placemark.coordinate
            annotation.title = item.name
            annotation.subtitle = placemark.title
            uiView.addAnnotation(annotation)
        }

        // Handle selected place
        if let selectedPlace = selectedPlace {
            let placemark = selectedPlace.placemark
            let annotation = MKPointAnnotation()
            annotation.coordinate = placemark.coordinate
            annotation.title = selectedPlace.name
            annotation.subtitle = placemark.title
            uiView.addAnnotation(annotation)

            let region = MKCoordinateRegion(
                center: placemark.coordinate,
                latitudinalMeters: selectedPlaceZoomMeters,
                longitudinalMeters: selectedPlaceZoomMeters
            )
            uiView.setRegion(region, animated: true)
            return
        }

        // Update region based on location manager
        if uiView.region.center.latitude != locationManager.region.center.latitude ||
           uiView.region.center.longitude != locationManager.region.center.longitude {
            uiView.setRegion(locationManager.region, animated: true)
        }

        // Add car+walk route segments
        if let carWalkRoute = carWalkRoute {
            addCarWalkRouteToMap(uiView, route: carWalkRoute)
        }
    }
    
    private func addCarWalkRouteToMap(_ mapView: MKMapView, route: CarWalkRouteResponse) {
        var allCoordinates: [CLLocationCoordinate2D] = []
        
        for (index, step) in route.steps.enumerated() {
            let startCoord = step.fromCoord.clLocationCoordinate
            let endCoord = step.toCoord.clLocationCoordinate
            
            // Add start and end annotations
            if index == 0 {
                let startAnnotation = MKPointAnnotation()
                startAnnotation.coordinate = startCoord
                startAnnotation.title = "Start"
                startAnnotation.subtitle = "Trip begins here"
                mapView.addAnnotation(startAnnotation)
            }
            
            if index == route.steps.count - 1 {
                let endAnnotation = MKPointAnnotation()
                endAnnotation.coordinate = endCoord
                endAnnotation.title = "Destination"
                endAnnotation.subtitle = "Trip ends here"
                mapView.addAnnotation(endAnnotation)
            }
            
            // Create polyline for this segment
            let coordinates = [startCoord, endCoord]
            let polyline = ColoredPolyline(coordinates: coordinates, count: coordinates.count)
            polyline.transportMode = step.transportType
            polyline.stepIndex = index
            
            mapView.addOverlay(polyline)
            allCoordinates.append(contentsOf: coordinates)
            
            // Add intermediate point annotation (transition point)
            if index < route.steps.count - 1 {
                let transitionAnnotation = MKPointAnnotation()
                transitionAnnotation.coordinate = endCoord
                transitionAnnotation.title = getTransitionTitle(from: step.transportType, to: route.steps[index + 1].transportType)
                transitionAnnotation.subtitle = "Switch transport mode"
                mapView.addAnnotation(transitionAnnotation)
            }
        }
        
        // Fit the entire route in view
        if !allCoordinates.isEmpty {
            let polyline = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 80, left: 80, bottom: 80, right: 80),
                animated: true
            )
        }
    }
    
    private func getTransitionTitle(from: CarWalkTransportMode, to: CarWalkTransportMode) -> String {
        switch (from, to) {
        case (.car, .walk):
            return "Park & Walk"
        case (.walk, .car):
            return "Walk to Car"
        default:
            return "Transition Point"
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: EnhancedMapViewContainer
        
        init(_ parent: EnhancedMapViewContainer) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let coloredPolyline = overlay as? ColoredPolyline {
                let renderer = MKPolylineRenderer(polyline: coloredPolyline)
                renderer.strokeColor = UIColor(coloredPolyline.transportMode.color)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                
                // Add visual distinction between segments
                if coloredPolyline.transportMode == .walk {
                    renderer.lineDashPattern = [8, 4] // Dashed line for walking
                }
                
                return renderer
            }
            
            // Fallback for regular polylines
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 5
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            
            let identifier = "PlaceAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            // Customize annotation based on title
            if let markerView = annotationView as? MKMarkerAnnotationView {
                switch annotation.title {
                case "Start":
                    markerView.markerTintColor = .systemGreen
                    markerView.glyphImage = UIImage(systemName: "location.fill")
                case "Destination":
                    markerView.markerTintColor = .systemRed
                    markerView.glyphImage = UIImage(systemName: "flag.fill")
                case "Park & Walk":
                    markerView.markerTintColor = .systemOrange
                    markerView.glyphImage = UIImage(systemName: "parkingsign")
                default:
                    markerView.markerTintColor = .systemBlue
                }
            }
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            print("Selected annotation: \(view.annotation?.title ?? "Unknown")")
        }
    }
}

// MARK: - Colored Polyline for Multi-Modal Routes
class ColoredPolyline: MKPolyline {
    var transportMode: CarWalkTransportMode = .walk
    var stepIndex: Int = 0
}
