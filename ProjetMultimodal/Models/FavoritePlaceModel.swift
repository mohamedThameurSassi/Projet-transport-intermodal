import Foundation
import MapKit

struct FavoritePlaceModel: Codable, Identifiable {
    let id: UUID
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    
    init(from mapItem: MKMapItem) {
        self.id = UUID()
        self.name = mapItem.name ?? "Unknown Place"
        self.address = mapItem.placemark.title
        self.coordinate = mapItem.placemark.coordinate
    }
}

// Extension to make CLLocationCoordinate2D Codable
extension CLLocationCoordinate2D: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
}
