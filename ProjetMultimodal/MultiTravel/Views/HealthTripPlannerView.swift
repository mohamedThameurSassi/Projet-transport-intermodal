import SwiftUI
import MapKit

struct HealthTripPlannerView: View {
    let destination: MKMapItem
    let locationManager: LocationManager
    let onRouteSelected: (TripResponse.RouteOption) -> Void
    
    @StateObject private var transportSelection = TransportSelection()
    @StateObject private var healthTripService = HealthTripService()
    @Environment(\.presentationMode) var presentationMode
    @State private var showingResults = false
    @State private var exerciseMinutes: Double = 15
    @State private var exerciseType: HealthTransportType = .walking
    @State private var originMode: StartOriginMode = .current
    @State private var customStartText: String = ""
    @State private var customStartResults: [MKMapItem] = []
    @State private var isSearchingStart: Bool = false
    @State private var customStartItem: MKMapItem? = nil

    enum StartOriginMode: String, CaseIterable {
        case current
        case custom
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("Healthy Routes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Find active alternatives")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Color(.systemBackground)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                )
                
                if !showingResults {
                    tripSetupView
                } else {
                    routeResultsView
                }
                
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private var tripSetupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Enhanced Destination Info Card
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
                
                // Enhanced Transport Selection
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you usually use?")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("We'll find healthier alternatives to your usual transport")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 12) {
                        ForEach(PreferredTransportType.allCases, id: \.self) { transportType in
                            EnhancedTransportOptionCard(
                                transportType: transportType,
                                isSelected: transportSelection.isSelected(transportType),
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        transportSelection.selectPreferred(transportType)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Start location selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start location")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    Picker("Origin", selection: $originMode) {
                        Text("Current location").tag(StartOriginMode.current)
                        Text("Custom place").tag(StartOriginMode.custom)
                    }
                    .pickerStyle(.segmented)

                    if originMode == .custom {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                                TextField("Search a start place", text: $customStartText)
                                    .textInputAutocapitalization(.words)
                                    .onChange(of: customStartText) { _ in
                                        searchStartPlaces()
                                    }
                                if !customStartText.isEmpty {
                                    Button(action: {
                                        customStartText = ""
                                        customStartResults = []
                                    }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                            if isSearchingStart {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Searching...").foregroundColor(.secondary)
                                }
                            }

                            if let chosen = customStartItem {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.and.ellipse").foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chosen.name ?? "Selected place")
                                            .font(.system(size: 14, weight: .semibold))
                                        if let addr = chosen.placemark.title {
                                            Text(addr).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Button("Clear") { customStartItem = nil }
                                        .buttonStyle(.bordered)
                                }
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            }

                            if !customStartResults.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(customStartResults.prefix(6)), id: \.self) { item in
                                        Button(action: {
                                            customStartItem = item
                                            customStartText = item.name ?? item.placemark.title ?? ""
                                            customStartResults = []
                                        }) {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "mappin").foregroundColor(.red)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name ?? "Place")
                                                        .font(.system(size: 14, weight: .semibold))
                                                    if let addr = item.placemark.title {
                                                        Text(addr)
                                                            .font(.system(size: 12))
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(2)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(12)
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "location.circle.fill").foregroundColor(.blue)
                            Text("Using your current location")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Exercise preferences
                VStack(alignment: .leading, spacing: 16) {
                    Text("Exercise preferences")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        Text("Type")
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Type", selection: $exerciseType) {
                            Text("Walking").tag(HealthTransportType.walking)
                            Text("Biking").tag(HealthTransportType.biking)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Time: \(Int(exerciseMinutes)) min")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Slider(value: $exerciseMinutes, in: 5...60, step: 5)
                    }
                }
                .padding(.horizontal, 20)
                
                // Enhanced Get Healthy Alternatives Button
                Button(action: {
                    requestHealthyAlternatives()
                }) {
                    HStack(spacing: 12) {
                        if healthTripService.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            
                            Text("Finding routes...")
                        } else {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 16, weight: .medium))
                            
                            Text("Find Healthy Alternatives")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: healthTripService.isLoading ? [.gray] : [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(
                        color: healthTripService.isLoading ? .clear : .green.opacity(0.3),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                }
                .disabled(healthTripService.isLoading || !canRequest)
                .scaleEffect(healthTripService.isLoading ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: healthTripService.isLoading)
                .padding(.horizontal, 20)
                
                // Error Display
                if let error = healthTripService.error {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    private var routeResultsView: some View {
        VStack(spacing: 0) {
            if let response = healthTripService.lastResponse {
                ScrollView {
                    VStack(spacing: 20) {
                        // Your Usual Route Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: response.originalRoute.segments.first?.transportType.icon ?? "car.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.blue)
                                
                                Text("Your Usual Route")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            
                            EnhancedRouteOptionRow(
                                route: response.originalRoute,
                                isOriginal: true,
                                onSelect: {
                                    onRouteSelected(response.originalRoute)
                                    presentationMode.wrappedValue.dismiss()
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        // Healthy Alternatives Section
                        if !response.healthAlternatives.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.green)
                                    
                                    Text("Healthy Alternatives")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(response.healthAlternatives.count) options")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(8)
                                }
                                
                                VStack(spacing: 12) {
                                    ForEach(response.healthAlternatives, id: \.id) { route in
                                        EnhancedRouteOptionRow(
                                            route: route,
                                            isOriginal: false,
                                            onSelect: {
                                                onRouteSelected(route)
                                                presentationMode.wrappedValue.dismiss()
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            
            // Back Button
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingResults = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back to Options")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private func requestHealthyAlternatives() {
        let originCoord: CLLocationCoordinate2D
        let originAddr: String?

        switch originMode {
        case .current:
            guard let last = locationManager.lastLocation else {
                healthTripService.error = "Unable to get your current location"
                return
            }
            originCoord = last.coordinate
            originAddr = nil
        case .custom:
            guard let item = customStartItem else {
                healthTripService.error = "Please choose a start location"
                return
            }
            originCoord = item.placemark.coordinate
            originAddr = item.placemark.title
        }

        Task {
            await healthTripService.requestHealthyAlternatives(
                origin: originCoord,
                destination: destination.placemark.coordinate,
                originAddress: originAddr,
                destinationAddress: destination.placemark.title,
                preferredTransport: transportSelection.selectedPreferredType,
                exerciseMinutes: exerciseMinutes,
                exerciseType: exerciseType
            )

            if healthTripService.error == nil {
                showingResults = true
            }
        }
    }

    private var canRequest: Bool {
        if healthTripService.isLoading { return false }
        if originMode == .custom { return customStartItem != nil }
        return true
    }

    private func searchStartPlaces() {
        guard originMode == .custom else { return }
        let text = customStartText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            customStartResults = []
            isSearchingStart = false
            return
        }
        isSearchingStart = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        if let last = locationManager.lastLocation {
            req.region = MKCoordinateRegion(center: last.coordinate, latitudinalMeters: 15000, longitudinalMeters: 15000)
        }
        MKLocalSearch(request: req).start { resp, _ in
            DispatchQueue.main.async {
                self.isSearchingStart = false
                self.customStartResults = resp?.mapItems ?? []
            }
        }
    }
}

struct EnhancedTransportOptionCard: View {
    let transportType: PreferredTransportType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon with animated background
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white : transportType.color.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    
                    Image(systemName: transportType.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ? transportType.color : transportType.color)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(transportType.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(transportType.description)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? 
                          LinearGradient(colors: [transportType.color, transportType.color.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [Color(.systemBackground)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(
                        color: isSelected ? transportType.color.opacity(0.3) : .black.opacity(0.05),
                        radius: isSelected ? 12 : 6,
                        x: 0,
                        y: isSelected ? 8 : 3
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Extension to add colors and descriptions to PreferredTransportType
extension PreferredTransportType {
    var color: Color {
        switch self {
        case .car: return .blue
        case .gtfs: return .green
        }
    }
    
    var description: String {
        switch self {
        case .car: return "Personal vehicle, door-to-door convenience"
    case .gtfs: return "Public transit, eco-friendly option"
        }
    }
}

struct EnhancedRouteOptionRow: View {
    let route: TripResponse.RouteOption
    let isOriginal: Bool
    let onSelect: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 16) {
                // Header with health score
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isOriginal ? "Your usual route" : "Healthy alternative")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isOriginal ? .blue : .green)
                        
                        Text(routeDescription)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Health Score Badge
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                        Text("\(route.healthScore)/10")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(healthScoreColor)
                    .cornerRadius(8)
                }
                
                // Transport segments
                if route.segments.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(route.segments.enumerated()), id: \.offset) { index, segment in
                                HStack(spacing: 4) {
                                    Image(systemName: segment.transportType.icon)
                                        .font(.system(size: 10))
                                    Text(segment.transportType.displayName)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                                
                                if index < route.segments.count - 1 {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                } else if let segment = route.segments.first {
                    HStack(spacing: 8) {
                        Image(systemName: segment.transportType.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text(segment.transportType.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                
                // Stats grid
                HStack(spacing: 0) {
                    StatCard(
                        icon: "clock.fill",
                        value: safeMinutes(route.totalDuration),
                        color: .blue
                    )
                    
                    StatCard(
                        icon: "flame.fill",
                        value: "\(route.estimatedCalories) cal",
                        color: .orange
                    )
                    
                    StatCard(
                        icon: "leaf.fill",
                        value: safeKg(route.carbonFootprint),
                        color: .green
                    )
                    
                    StatCard(
                        icon: "ruler.fill",
                        value: safeKm(route.totalDistance),
                        color: .purple
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: .black.opacity(isPressed ? 0.15 : 0.08),
                        radius: isPressed ? 12 : 8,
                        x: 0,
                        y: isPressed ? 6 : 4
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
    
    private var healthScoreColor: Color {
        switch route.healthScore {
        case 8...10: return .green
        case 5...7: return .orange
        default: return .red
        }
    }
    
    private var routeDescription: String {
        if route.segments.count > 1 {
            return "Multi-modal journey"
        } else if let segment = route.segments.first {
            return "Via \(segment.transportType.displayName.lowercased())"
        }
        return "Route option"
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Safe formatters to avoid NaN/Inf in UI
private func safeMinutes(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite && !seconds.isNaN else { return "– min" }
    let mins = max(0, Int(seconds / 60))
    return "\(mins) min"
}

private func safeKm(_ meters: Double) -> String {
    guard meters.isFinite && !meters.isNaN else { return "– km" }
    return String(format: "%.1f km", meters / 1000.0)
}

private func safeKg(_ kg: Double) -> String {
    guard kg.isFinite && !kg.isNaN else { return "– kg" }
    return String(format: "%.1f kg", kg)
}
