import Foundation
import CoreLocation

class HealthTripService: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: TripResponse?
    @Published var error: String?
    
    private let baseURL = "http://localhost:8080"
    private let session = URLSession.shared
    
    func requestHealthyAlternatives(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        originAddress: String?,
        destinationAddress: String?,
        preferredTransport: PreferredTransportType
    ) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        let request = TripRequest(
            origin: TripRequest.LocationPoint(
                latitude: origin.latitude,
                longitude: origin.longitude,
                address: originAddress
            ),
            destination: TripRequest.LocationPoint(
                latitude: destination.latitude,
                longitude: destination.longitude,
                address: destinationAddress
            ),
            preferredTransport: preferredTransport.serverValue,
            requestTime: Date()
        )
        
        do {
            let response = try await sendTripRequest(request)
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
    
    private func sendTripRequest(_ request: TripRequest) async throws -> TripResponse {
        guard let url = URL(string: "\(baseURL)/api/health-route") else {
            throw TripServiceError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonData = try JSONEncoder().encode(request)
        urlRequest.httpBody = jsonData
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw TripServiceError.serverError
        }
        
        let tripResponse = try JSONDecoder().decode(TripResponse.self, from: data)
        return tripResponse
    }
}

enum TripServiceError: LocalizedError {
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
