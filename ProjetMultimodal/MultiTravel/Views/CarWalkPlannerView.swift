import SwiftUI
import MapKit

struct CarWalkPlannerView: View {
    let destination: MKMapItem
    let locationManager: LocationManager
    let onRouteCalculated: (CarWalkRouteResponse) -> Void
    
    @StateObject private var carWalkService = CarWalkRoutingService()
    @Environment(\.presentationMode) var presentationMode
    @State private var walkDurationMinutes: Double = 20
    @State private var showingRouteDetails = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                
                if !showingRouteDetails {
                    planningView
                } else {
                    routeDetailsView
                }
                
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.blue)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Car + Walk Route")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Drive, then walk to destination")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("") { }
                .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
    
    private var planningView: some View {
        ScrollView {
            VStack(spacing: 24) {
                destinationInfoCard
                walkingDurationCard
                planRouteButton
                
                if let error = carWalkService.error {
                    errorCard(error: error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var destinationInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("Destination")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Text(destination.name ?? "Unknown Place")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            if let address = destination.placemark.title {
                Text(address)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var walkingDurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
                
                Text("Walking Duration")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text("How long are you willing to walk from the parking spot?")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                HStack {
                    Text("\\(Int(walkDurationMinutes)) minutes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Text("~\\(String(format: \"%.1f\", walkDurationMinutes * 1.4 * 60 / 1000)) km")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $walkDurationMinutes, in: 5...30, step: 5)
                    .accentColor(.green)
                
                HStack {
                    Text("5 min")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("30 min")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private var planRouteButton: some View {
        Button(action: planRoute) {
            HStack(spacing: 12) {
                if carWalkService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Plan Car + Walk Route")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: carWalkService.isLoading ? [.gray] : [.blue, .cyan]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(
                color: carWalkService.isLoading ? .clear : .blue.opacity(0.3),
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .disabled(carWalkService.isLoading)
        .scaleEffect(carWalkService.isLoading ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: carWalkService.isLoading)
    }
    
    private var routeDetailsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let response = carWalkService.lastResponse {
                    routeSummaryCard(response: response)
                    routeStepsCard(response: response)
                    useRouteButton(response: response)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private func routeSummaryCard(response: CarWalkRouteResponse) -> some View {
        VStack(spacing: 16) {
            Text("Route Summary")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            HStack(spacing: 20) {
                VStack {
                    Text("\\(formatTime(response.totalDurationSec))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Total Time")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\\(formatDistance(response.totalDistanceM))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Total Distance")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 20) {
                VStack {
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.blue)
                        Text("\\(formatTime(response.carDurationSec))")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("\\(formatDistance(response.carDistanceM))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    HStack {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.green)
                        Text("\\(formatTime(response.walkDurationSec))")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("\\(formatDistance(response.walkDistanceM))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private func routeStepsCard(response: CarWalkRouteResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Route Steps")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            ForEach(Array(response.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Image(systemName: step.transportType.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(step.transportType.color))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.description)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\\(formatTime(step.durationSec))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text("\\(formatDistance(step.distanceM))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                
                if index < response.steps.count - 1 {
                    Divider()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private func useRouteButton(response: CarWalkRouteResponse) -> some View {
        Button(action: {
            onRouteCalculated(response)
            presentationMode.wrappedValue.dismiss()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 16, weight: .medium))
                
                Text("Use This Route")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.green, .mint]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    private func errorCard(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func planRoute() {
        guard let userLocation = locationManager.lastLocation else {
            carWalkService.error = "Unable to get your current location"
            return
        }
        
        Task {
            await carWalkService.requestCarWalkRoute(
                origin: userLocation.coordinate,
                destination: destination.placemark.coordinate,
                walkDurationMinutes: walkDurationMinutes
            )
            
            if carWalkService.error == nil && carWalkService.lastResponse != nil {
                showingRouteDetails = true
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\\(hours)h \\(remainingMinutes)m"
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\\(Int(meters)) m"
        } else {
            let kilometers = meters / 1000
            return String(format: "%.1f km", kilometers)
        }
    }
}
