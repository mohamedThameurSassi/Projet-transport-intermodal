import SwiftUI
import MapKit

// MARK: - Directions View
struct DirectionsView: View {
    let destination: MKMapItem
    let locationManager: LocationManager
    let onRouteCalculated: (MKRoute) -> Void
    
    @StateObject private var transportSelection = TransportSelection()
    @State private var isCalculating = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Spacer()
                
                Text("Select Transport Types")
                    .font(.headline)
                
                Spacer()
                
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .opacity(0) // Hidden but maintains spacing
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
            
            // Destination Info
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(destination.name ?? "Unknown Place")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let address = destination.placemark.title {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            // Transport Type Selection
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your transport options")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(TransportType.allCases, id: \.self) { type in
                        Button(action: {
                            transportSelection.toggle(type)
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: iconForTransportType(type))
                                    .font(.title2)
                                Text(type.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(transportSelection.isSelected(type) ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(transportSelection.isSelected(type) ? Color.blue : Color(.systemGray5))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // Get Multitravel Directions Button
            Button(action: {
                sendTravelRequestToServer()
            }) {
                HStack {
                    if isCalculating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Computing...")
                    } else {
                        Text("Get Multitravel Directions")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(transportSelection.selectedTypes.isEmpty || isCalculating ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(transportSelection.selectedTypes.isEmpty || isCalculating)
            .padding()
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.5) // Half of screen height
        .background(Color(.systemBackground))
    }
    
    private func iconForTransportType(_ type: TransportType) -> String {
        switch type {
        case .automobile: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .bixi: return "bicycle"
        case .bike: return "bicycle"
        }
    }
    
    private func sendTravelRequestToServer() {
        guard let userLocation = locationManager.lastLocation else { return }
        
        isCalculating = true
        
        let requestData = TravelRequest(
            startLatitude: userLocation.coordinate.latitude,
            startLongitude: userLocation.coordinate.longitude,
            endLatitude: destination.placemark.coordinate.latitude,
            endLongitude: destination.placemark.coordinate.longitude,
            transportTypes: Array(transportSelection.selectedTypes)
        )
        
        // Send to GO server
        sendToGoServer(requestData: requestData) { result in
            DispatchQueue.main.async {
                self.isCalculating = false
                
                switch result {
                case .success(let response):
                    // Handle successful response from server
                    print("Received server response: \(response)")
                    // Process the response and create TravelSteps as needed
                    self.presentationMode.wrappedValue.dismiss()
                    
                case .failure(let error):
                    // Handle error
                    print("Error: \(error)")
                    // Show error alert or handle appropriately
                }
            }
        }
    }
    
    private func sendToGoServer(requestData: TravelRequest, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://your-go-server.com/api/travel-steps") else {
            completion(.failure(NetworkError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(requestData)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NetworkError.noData))
                    return
                }
              
                if let responseString = String(data: data, encoding: .utf8) {
                    completion(.success(responseString))
                } else {
                    completion(.failure(NetworkError.noData))
                }
            }.resume()
            
        } catch {
            completion(.failure(error))
        }
    }
}

struct TravelRequest: Codable {
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double
    let transportTypes: [TransportType]
}

enum NetworkError: Error {
    case invalidURL
    case noData
}
