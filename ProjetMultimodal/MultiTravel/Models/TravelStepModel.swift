import MapKit
import CoreLocation

struct TravelSteps {
    let directions: MKDirections.Response
    let transportType: HealthTransportType
    let startLocation: CLLocationCoordinate2D
    let endLocation: CLLocationCoordinate2D
    let startAddress: String?
    let endAddress: String?
    let estimatedTravelTime: TimeInterval
    let distance: CLLocationDistance
    
    init(directions: MKDirections.Response,
         startLocation: CLLocationCoordinate2D,
         endLocation: CLLocationCoordinate2D,
         transportType: HealthTransportType,
         startAddress: String? = nil,
         endAddress: String? = nil) {
        
        self.directions = directions
        self.startLocation = startLocation
        self.endLocation = endLocation
        self.transportType = transportType
        self.startAddress = startAddress
        self.endAddress = endAddress
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
