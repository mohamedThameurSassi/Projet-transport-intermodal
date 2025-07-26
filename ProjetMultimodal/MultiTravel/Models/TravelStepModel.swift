
import MapKit
import CoreLocation

struct TravelSteps{
    let directions: MKDirections.Response
    let transportType: TransportType
    let startLocation: CLLocationCoordinate2D
    let endLocation: CLLocationCoordinate2D
    let startAdress: String?
    let endAdress: String?
    let estimatedTravelTime: TimeInterval
    let distance: CLLocationDistance
    
    init(directions: MKDirections.Response,
    startLocation: CLLocationCoordinate2D,
    endLocation: CLLocationCoordinate2D,
    transportType: TransportType,
    startAdress: String? = nil,
         endAdress: String? = nil) {
        
        self.directions = directions
        self.startLocation = startLocation
        self.endLocation = endLocation
        self.transportType = transportType
        self.startAdress = startAdress
        self.endAdress = endAdress
        self.estimatedTravelTime = directions.routes.first?.expectedTravelTime ?? 0
        self.distance = directions.routes.first?.distance ?? 0
    }
    
    var primaryRoute: MKRoute? {
        return directions.routes.first
    }
    var stepInstructions: [String] {
        return primaryRoute?.steps.map { $0.instructions } ?? []
        
    }
    var polyline: MKPolyline? {
        return primaryRoute?.polyline
    }
    
}
