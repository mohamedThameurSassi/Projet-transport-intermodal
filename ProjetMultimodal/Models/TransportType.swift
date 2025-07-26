import MapKit

enum TransportType: Int, CaseIterable, Hashable, Codable {
    case automobile = 0
    case walking = 1
    case transit = 2
    case bixi = 3
    case bike = 4
    
    var mkDirectionsType: MKDirectionsTransportType {
        switch self {
        case .automobile: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        case .bixi, .bike:
            if #available(iOS 14.0, *) {
                return .automobile
            } else {
                return .automobile
            }
        }
    }
    
    var displayName: String {
        switch self {
        case .automobile: return "Drive"
        case .walking: return "Walk"
        case .transit: return "Transit"
        case .bixi: return "Bixi"
        case .bike: return "Bike"
        }
    }
    
}

struct MultiTransportRoute {
    let transportTypes: Set<TransportType>
    
    init(_ types: TransportType...) {
        self.transportTypes = Set(types)
    }
    
    func getMKDirectionsTransportTypes() -> [MKDirectionsTransportType] {
        return transportTypes.map { $0.mkDirectionsType }
    }
    
    func getDisplayNames() -> [String] {
        return transportTypes.map { $0.displayName }
    }
}
