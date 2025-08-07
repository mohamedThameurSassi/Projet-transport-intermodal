import Foundation
import CoreLocation
import SwiftUI

class CarWalkRoutingService: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: CarWalkRouteResponse?
    @Published var error: String?
    
    private let baseURL = "http://localhost:8080"
    private let session = URLSession.shared
    
    func requestCarWalkRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        walkDurationMinutes: Double = 20
    ) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        let request = CarWalkRouteRequest(
            startLat: origin.latitude,
            startLon: origin.longitude,
            endLat: destination.latitude,
            endLon: destination.longitude,
            walkDurationMins: walkDurationMinutes
        )
        
        do {
            let response = try await sendCarWalkRequest(request)
            await MainActor.run {
                self.lastResponse = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func sendCarWalkRequest(_ request: CarWalkRouteRequest) async throws -> CarWalkRouteResponse {
        guard let url = URL(string: "\(baseURL)/route/car-walk") else {
            throw CarWalkServiceError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonData = try JSONEncoder().encode(request)
        urlRequest.httpBody = jsonData
        
        print("🚗 Sending car+walk request to: \(url)")
        print("📝 Request body: \(String(data: jsonData, encoding: .utf8) ?? "unknown")")
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CarWalkServiceError.serverError
        }
        
        print("📡 Response status: \(httpResponse.statusCode)")
        
        guard 200...299 ~= httpResponse.statusCode else {
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ Server error response: \(errorData)")
            }
            throw CarWalkServiceError.serverError
        }
        
        print("✅ Response data: \(String(data: data, encoding: .utf8) ?? "unknown")")
        
        let carWalkResponse = try JSONDecoder().decode(CarWalkRouteResponse.self, from: data)
        return carWalkResponse
    }
}

// MARK: - Request/Response Models

struct CarWalkRouteRequest: Codable {
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let walkDurationMins: Double
}

struct CarWalkRouteResponse: Codable {
    let steps: [CarWalkRouteStep]
    let totalDistanceM: Double
    let totalDurationSec: Double
    let walkDistanceM: Double
    let walkDurationSec: Double
    let carDistanceM: Double
    let carDurationSec: Double
    let error: String?
}

struct CarWalkRouteStep: Codable {
    let mode: String // "car" or "walk_final" 
    let fromCoord: Coordinate
    let toCoord: Coordinate
    let durationSec: Double
    let distanceM: Double
    let description: String
    let error: String?
    
    // CodingKeys to map server's capitalized field names to Swift camelCase
    enum CodingKeys: String, CodingKey {
        case mode = "Mode"
        case fromCoord = "FromCoord"
        case toCoord = "ToCoord"
        case durationSec = "DurationSec"
        case distanceM = "DistanceM"
        case description = "Description"
        case error = "Error"
    }
    
    // Map mode to transport type
    var transportType: CarWalkTransportMode {
        switch mode.lowercased() {
        case "car":
            return .car
        case "walk_final", "walk":
            return .walk
        default:
            return .walk
        }
    }
    
    struct Coordinate: Codable {
        let lat: Double
        let lon: Double
        
        // CodingKeys to map server's capitalized field names to Swift camelCase
        enum CodingKeys: String, CodingKey {
            case lat = "Lat"
            case lon = "Lon"
        }
        
        var clLocationCoordinate: CLLocationCoordinate2D {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

enum CarWalkTransportMode: String, CaseIterable {
    case car = "car"
    case walk = "walk"
    
    var displayName: String {
        switch self {
        case .car: return "Drive"
        case .walk: return "Walk"
        }
    }
    
    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .walk: return "figure.walk"
        }
    }
    
    var color: Color {
        switch self {
        case .car: return .blue
        case .walk: return .green
        }
    }
}

enum CarWalkServiceError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error occurred"
        case .decodingError:
            return "Failed to parse server response"
        }
    }
}
