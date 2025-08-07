import MapKit

// User's preferred transport types (what they usually use)
enum PreferredTransportType: Int, CaseIterable, Hashable, Codable {
    case car = 0
    case gtfs = 1  // Public transit (GTFS)
    
    var displayName: String {
        switch self {
        case .car: return "Car"
        case .gtfs: return "Public Transit"
        }
    }
    
    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .gtfs: return "bus.fill"
        }
    }
    
    var serverValue: String {
        switch self {
        case .car: return "car"
        case .gtfs: return "gtfs"
        }
    }
}

// Transport types for health-oriented alternatives
enum HealthTransportType: String, CaseIterable, Hashable, Codable {
    case walking = "walking"
    case biking = "biking"
    case transit = "transit"
    case driving = "driving"
    
    var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .biking: return "Biking"
        case .transit: return "Transit"
        case .driving: return "Driving"
        }
    }
    
    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .biking: return "bicycle"
        case .transit: return "bus.fill"
        case .driving: return "car.fill"
        }
    }
    
    var healthBenefit: String {
        switch self {
        case .walking: return "Great cardio workout"
        case .biking: return "Excellent full-body exercise"
        case .transit: return "Some walking to/from stops"
        case .driving: return "No physical activity"
        }
    }
}

// MARK: - Trip Request/Response Models for Go Server Communication

struct TripRequest: Codable {
    let origin: LocationPoint
    let destination: LocationPoint
    let preferredTransport: String
    let requestTime: Date
    
    struct LocationPoint: Codable {
        let latitude: Double
        let longitude: Double
        let address: String?
    }
}

struct TripResponse: Codable {
    let originalRoute: RouteOption
    let healthAlternatives: [RouteOption]
    let requestId: String
    
    struct RouteOption: Codable {
        let id: String
        let segments: [RouteSegment]
        let totalDuration: TimeInterval
        let totalDistance: Double
        let estimatedCalories: Int
        let healthScore: Int // 1-10 scale
        let carbonFootprint: Double // kg CO2
        
        struct RouteSegment: Codable {
            let transportType: HealthTransportType
            let duration: TimeInterval
            let distance: Double
            let instructions: String
            let startLocation: TripRequest.LocationPoint
            let endLocation: TripRequest.LocationPoint
            let polyline: String? // Encoded polyline for map display
        }
    }
}

struct MultiTransportRoute {
    let transportTypes: Set<PreferredTransportType>
    
    init(_ types: PreferredTransportType...) {
        self.transportTypes = Set(types)
    }
    
    func getDisplayNames() -> [String] {
        return transportTypes.map { $0.displayName }
    }
}
