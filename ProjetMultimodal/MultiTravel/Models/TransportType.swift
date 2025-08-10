import MapKit
import SwiftUI

enum PreferredTransportType: Int, CaseIterable, Hashable, Codable {
    case car = 0
    case gtfs = 1 
    
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

    // Accept server synonyms during decode
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "driving", "car": self = .driving
        case "transit", "gtfs": self = .transit
        case "walking", "walk", "walk_final", "walk_to_transit", "walk_from_transit": self = .walking
        case "biking", "bike", "cycling": self = .biking
        default:
            if let v = HealthTransportType(rawValue: raw) {
                self = v
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown transport type: \(raw)")
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
    
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

extension HealthTransportType {
    var color: Color {
        switch self {
        case .walking:
            return .red
        case .biking:
            if #available(iOS 15.0, *) {
                return .teal
            } else {
                return Color(.systemTeal)
            }
        case .transit:
            return .purple
        case .driving:
            return .blue
        }
    }
}


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
        let healthScore: Int
        let carbonFootprint: Double 
        
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
