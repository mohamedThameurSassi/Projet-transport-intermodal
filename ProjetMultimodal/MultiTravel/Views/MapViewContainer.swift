import SwiftUI
import MapKit

// MARK: - Map View Container
struct MapViewContainer: UIViewRepresentable {
    let locationManager: LocationManager
    let mapType: MKMapType
    let searchResults: [MKMapItem]
    let selectedPlace: MKMapItem?
    let currentRoute: MKRoute?
    @Binding var userTrackingMode: MKUserTrackingMode
    
    // Zoom level constants
    private let defaultZoomMeters: CLLocationDistance = 500 // Closer zoom
    private let selectedPlaceZoomMeters: CLLocationDistance = 300 // Even closer for selected places
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = userTrackingMode
        mapView.mapType = mapType
        
        // Always start with Montreal region - this ensures proper initial zoom
        let montrealRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673),
            latitudinalMeters: 2000, // 2km view
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

        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        uiView.removeOverlays(uiView.overlays)

        for item in searchResults {
            let placemark = item.placemark
            let annotation = MKPointAnnotation()
            annotation.coordinate = placemark.coordinate
            annotation.title = item.name
            annotation.subtitle = placemark.title
            uiView.addAnnotation(annotation)
        }

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

        // Update region based on location manager's region (this handles Montreal default + user location updates)
        if uiView.region.center.latitude != locationManager.region.center.latitude ||
           uiView.region.center.longitude != locationManager.region.center.longitude {
            uiView.setRegion(locationManager.region, animated: true)
        }

        if let route = currentRoute {
            uiView.addOverlay(route.polyline)
            uiView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: true)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewContainer
        
        init(_ parent: MapViewContainer) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
            
            return annotationView
        }
        
        // Handle POI (Points of Interest) selection
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            print("Selected annotation: \(view.annotation?.title ?? "Unknown")")
            
            // Handle custom annotations (search results)
            if let annotation = view.annotation, !(annotation is MKUserLocation) {
                print("Selected place: \(annotation.title ?? "Unknown")")
                // You could trigger navigation here or show more details
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update shared region so search completer stays relevant
            DispatchQueue.main.async {
                self.parent.locationManager.region = mapView.region
            }
        }
    }
}
