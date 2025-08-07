import Foundation
import CoreLocation
import MapKit

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var lastLocation: CLLocation?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673), // Montreal coordinates
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Much closer zoom
    )
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Set initial region to Montreal with proper zoom
        setMontrealRegion()
    }
    
    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        manager.requestLocation()
    }
    
    // Force update to Montreal if no location is available
    func ensureProperRegion() {
        if lastLocation == nil {
            setMontrealRegion()
        }
    }
    
    // Set default region to Montreal with proper zoom
    private func setMontrealRegion() {
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673),
                latitudinalMeters: 2000, // 2km view - good for city overview
                longitudinalMeters: 2000
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.lastLocation = location
            // When we get user location, zoom closer
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 1000, // 1km view - closer for user location
                longitudinalMeters: 1000
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        // If location fails, ensure we stay on Montreal
        setMontrealRegion()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            print("Location access denied - staying on Montreal")
            setMontrealRegion()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            setMontrealRegion()
        }
    }
}