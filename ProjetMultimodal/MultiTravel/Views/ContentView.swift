import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var favoritesManager = FavoritesManager()
    @State private var searchText = ""
    @State private var selectedMapType: MKMapType = .standard
    @State private var showingSearchResults = false
    @State private var showingFavorites = false
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedPlace: MKMapItem?
    @State private var showingDirections = false
    @State private var currentRoute: MKRoute?
    @State private var showingSettings = false
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var isStartingNavigation = false
    
    // Car+Walk routing support
    @State private var showingCarWalkPlanner = false
    @State private var currentCarWalkRoute: CarWalkRouteResponse?

    // Health route follow mode
    @State private var selectedHealthRoute: TripResponse.RouteOption?
    @State private var healthOverlays: [HealthSegmentOverlay] = []
    @State private var activeHealthSegmentIndex: Int? = nil
    
    @State private var searchCompleter = MKLocalSearchCompleter()
    @State private var searchSuggestions: [MKLocalSearchCompletion] = []
    @State private var selectedPOICategory: MKPointOfInterestCategory?
    @State private var poiResults: [MKMapItem] = []
    @State private var completerDelegate: SearchCompleterDelegate?

    var body: some View {
        ZStack {
        if currentCarWalkRoute != nil || !healthOverlays.isEmpty {
                EnhancedMapViewContainer(
                    locationManager: locationManager,
                    mapType: selectedMapType,
                    searchResults: searchResults,
                    selectedPlace: selectedPlace,
                    carWalkRoute: currentCarWalkRoute,
                    healthOverlays: healthOverlays.isEmpty ? nil : healthOverlays,
                    activeHealthSegmentIndex: activeHealthSegmentIndex,
                    userTrackingMode: $userTrackingMode
                )
                .edgesIgnoringSafeArea(.all)
            } else {
                MapViewContainer(
                    locationManager: locationManager,
                    mapType: selectedMapType,
                    searchResults: searchResults,
                    selectedPlace: selectedPlace,
                    currentRoute: currentRoute,
                    userTrackingMode: $userTrackingMode
                )
                .edgesIgnoringSafeArea(.all)
            }
            
            VStack {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(searchText.isEmpty ? .gray : .blue)
                            .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
                        
                        TextField("Where would you like to go?", text: $searchText)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .onSubmit {
                                searchForPlaces()
                            }
                            .onTapGesture {
                                // If we have a selected place, clear it when user taps search field
                                if selectedPlace != nil {
                                    selectedPlace = nil
                                    searchText = ""
                                } else if !favoritesManager.favorites.isEmpty {
                                    showingFavorites = true
                                    showingSearchResults = false
                                }
                            }
                            .onChange(of: searchText) { _, newValue in
                                if newValue.isEmpty {
                                    showingSearchResults = false
                                    showingFavorites = false
                                    searchResults = []
                                    searchSuggestions = []
                                    selectedPlace = nil
                                } else {
                                    // Only update search completer if we don't have a selected place
                                    // This prevents the completer from running when we set searchText programmatically
                                    if selectedPlace == nil {
                                        searchCompleter.queryFragment = newValue
                                    }
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    clearSearch()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(
                                color: .black.opacity(0.1),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    )
                    
                    // Enhanced Settings Button
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .shadow(
                                        color: .black.opacity(0.1),
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                            )
                    }
                    .shadow(radius: 2)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // POI Filter Buttons
                if !searchText.isEmpty || selectedPOICategory != nil {
                    poiFilterButtons
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 10) {
                        // User Location Button
                        Button(action: {
                            locationManager.requestLocation()
                            userTrackingMode = userTrackingMode == .none ? .follow : .none
                        }) {
                            Image(systemName: userTrackingMode == .none ? "location" : "location.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .cornerRadius(22)
                                .shadow(radius: 2)
                        }
                        
                        Menu {
                            Button("Standard") {
                                selectedMapType = .standard
                            }
                            Button("Satellite") {
                                selectedMapType = .satellite
                            }
                            Button("Hybrid") {
                                selectedMapType = .hybrid
                            }
                        } label: {
                            Image(systemName: "map")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .cornerRadius(22)
                                .shadow(radius: 2)
                        }
                        
                        if selectedPlace != nil {
                            Button(action: {
                                showingDirections = true
                            }) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white)
                                    .cornerRadius(22)
                                    .shadow(radius: 2)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            
            // Favorites overlay
            if showingFavorites && !favoritesManager.favorites.isEmpty {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        HStack {
                            Text("Favorites")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                showingFavorites = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(favoritesManager.favorites, id: \.id) { favorite in
                                    FavoriteRow(favorite: favorite) {
                                        selectFavorite(favorite)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 250)
                        .background(Color.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 5)
                    .padding(.horizontal)
                }
            }
            
            // Enhanced Search Results and Suggestions
            if (showingSearchResults && !searchResults.isEmpty && selectedPlace == nil) || (!searchSuggestions.isEmpty && !searchText.isEmpty && selectedPlace == nil) {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // Results Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if !searchSuggestions.isEmpty && !searchText.isEmpty && searchResults.isEmpty {
                                    Text("Search Suggestions")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text("Type to see suggestions")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Search Results")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text("\(searchResults.count) places found")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    clearSearch()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .background(Color(.systemBackground))
                        
                        Divider()
                            .background(Color(.systemGray4))
                        
                        // Results List
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // Show suggestions when typing (but not when we have search results)
                                if !searchSuggestions.isEmpty && !searchText.isEmpty && searchResults.isEmpty {
                                    ForEach(searchSuggestions, id: \.title) { suggestion in
                                        SearchSuggestionRow(suggestion: suggestion) {
                                            selectSuggestion(suggestion)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                                
                                // Show search results (takes priority over suggestions)
                                ForEach(searchResults, id: \.self) { item in
                                    SearchResultRow(item: item) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            // Set selected place first to prevent onChange issues
                                            selectedPlace = item
                                            searchText = item.name ?? ""
                                            // Clear all overlays and suggestions
                                            showingSearchResults = false
                                            showingFavorites = false
                                            searchSuggestions = []
                                            searchResults = []
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .frame(maxHeight: 400)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .shadow(
                                color: .black.opacity(0.15),
                                radius: 20,
                                x: 0,
                                y: -8
                            )
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            if let place = selectedPlace, !showingSearchResults && !showingFavorites && selectedHealthRoute == nil && currentCarWalkRoute == nil {
                VStack {
                    Spacer()
                    
                    PlaceInfoActionCard(
                        place: place,
                        onClose: {
                            selectedPlace = nil
                            currentRoute = nil
                            currentCarWalkRoute = nil
                            clearHealthFollow()
                        },
                        onDirections: {
                            showingDirections = true
                        },
                        onCarWalkDirections: {
                            showingCarWalkPlanner = true
                        },
                        onFavoriteToggle: {
                            favoritesManager.toggleFavorite(place)
                        },
                        isFavorite: favoritesManager.isFavorite(place),
                        onGo: {
                            // Quick start navigation: open planner immediately
                            isStartingNavigation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingDirections = true
                                isStartingNavigation = false
                            }
                        },
                        isStartingNavigation: isStartingNavigation
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 50)
                }
            }

            // Follow UI overlays
            if let route = selectedHealthRoute, let idx = activeHealthSegmentIndex, route.segments.indices.contains(idx) {
                VStack {
                    Spacer()
                    TripFollowBar(
                        route: route,
                        activeIndex: idx,
                        onPrev: { moveToPrevSegment() },
                        onNext: { moveToNextSegment() },
                        onExit: { clearHealthFollow() }
                    )
                }
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: activeHealthSegmentIndex)

                // Optional top HUD with instruction for current segment
                VStack {
                    NavigationHUD(
                        segment: route.segments[idx],
                        index: idx,
                        total: route.segments.count,
                        onEnd: { clearHealthFollow() }
                    )
                    Spacer()
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingDirections) {
            if let place = selectedPlace {
                DirectionsView(
                    destination: place,
                    locationManager: locationManager
                ) { route in
                    currentRoute = route
                    currentCarWalkRoute = nil
                    showingDirections = false
                } onHealthRouteSelected: { option in
                    // Enter follow mode for health route
                    Task {
                        await startHealthFollow(with: option)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCarWalkPlanner) {
            if let place = selectedPlace {
                CarWalkPlannerView(
                    destination: place,
                    locationManager: locationManager
                ) { carWalkRoute in
                    currentCarWalkRoute = carWalkRoute
                    currentRoute = nil // Clear any existing standard route
                    selectedHealthRoute = nil
                    healthOverlays = []
                    activeHealthSegmentIndex = nil
                    showingCarWalkPlanner = false
                }
            }
        }
        .onAppear {
            locationManager.requestLocationPermission()
            // Ensure we start with proper region (Montreal) even if location permission is denied
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                locationManager.ensureProperRegion()
            }
            // Setup search completion
            setupSearchCompleter()
        }
    }

    // MARK: - Follow mode helpers
    private func startHealthFollow(with option: TripResponse.RouteOption) async {
        // Clear other route states
        currentRoute = nil
        currentCarWalkRoute = nil
        selectedPlace = nil
        
        // Compute MKRoute polylines for each segment
        let mkRoutes = await HealthTripService().computeMKRoutes(for: option)
        
        await MainActor.run {
            self.selectedHealthRoute = option
            self.healthOverlays = mkRoutes.enumerated().map { idx, route in
                HealthSegmentOverlay(
                    polyline: route.polyline,
                    mode: option.segments[idx].transportType
                )
            }
            self.activeHealthSegmentIndex = healthOverlays.isEmpty ? nil : 0
            self.showingDirections = false
        }
    }
    private func moveToPrevSegment() {
        guard var idx = activeHealthSegmentIndex else { return }
        idx = max(0, idx - 1)
        activeHealthSegmentIndex = idx
    }
    private func moveToNextSegment() {
        guard let route = selectedHealthRoute, var idx = activeHealthSegmentIndex else { return }
        let maxIndex = route.segments.count - 1
        idx = min(maxIndex, idx + 1)
        activeHealthSegmentIndex = idx
    }
    private func clearHealthFollow() {
        selectedHealthRoute = nil
        healthOverlays = []
        activeHealthSegmentIndex = nil
    }
    
    private func searchForPlaces() {
        guard !searchText.isEmpty else { return }
        
        showingFavorites = false
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = locationManager.region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else { return }
            
            DispatchQueue.main.async {
                self.searchResults = response.mapItems
                self.showingSearchResults = true
            }
        }
    }
    
    private func selectFavorite(_ favorite: FavoritePlaceModel) {
        let placemark = MKPlacemark(coordinate: favorite.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = favorite.name
        
        selectedPlace = mapItem
        searchText = favorite.name
        showingFavorites = false
        showingSearchResults = false
    }
    
    // MARK: - POI Filter Buttons
    private var poiFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Clear filter button
                POIFilterButton(
                    icon: "location.fill",
                    title: "All",
                    color: .blue,
                    isSelected: selectedPOICategory == nil
                ) {
                    clearPOIFilter()
                }
                
                // Restaurant button
                POIFilterButton(
                    icon: "fork.knife",
                    title: "Restaurants",
                    color: .orange,
                    isSelected: selectedPOICategory == .restaurant
                ) {
                    filterPOI(.restaurant)
                }
                
                // Gas Station button
                POIFilterButton(
                    icon: "fuelpump.fill",
                    title: "Gas",
                    color: .green,
                    isSelected: selectedPOICategory == .gasStation
                ) {
                    filterPOI(.gasStation)
                }
                
                // Hospital button
                POIFilterButton(
                    icon: "cross.case.fill",
                    title: "Hospital",
                    color: .red,
                    isSelected: selectedPOICategory == .hospital
                ) {
                    filterPOI(.hospital)
                }
                
                // Pharmacy button
                POIFilterButton(
                    icon: "pills.fill",
                    title: "Pharmacy",
                    color: .pink,
                    isSelected: selectedPOICategory == .pharmacy
                ) {
                    filterPOI(.pharmacy)
                }
                
                // Store button
                POIFilterButton(
                    icon: "bag.fill",
                    title: "Stores",
                    color: .blue,
                    isSelected: selectedPOICategory == .store
                ) {
                    filterPOI(.store)
                }
                
                // Transit button
                POIFilterButton(
                    icon: "bus.fill",
                    title: "Transit",
                    color: .mint,
                    isSelected: selectedPOICategory == .publicTransport
                ) {
                    filterPOI(.publicTransport)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Helper Methods
    private func setupSearchCompleter() {
        completerDelegate = SearchCompleterDelegate { suggestions in
            DispatchQueue.main.async {
                // Only update suggestions if we don't have a selected place
                // This prevents suggestions from appearing when we've already selected something
                if self.selectedPlace == nil {
                    self.searchSuggestions = suggestions
                }
            }
        }
        searchCompleter.delegate = completerDelegate
        searchCompleter.region = locationManager.region
        searchCompleter.resultTypes = [.address, .pointOfInterest]
    }
    
    private func filterPOI(_ category: MKPointOfInterestCategory) {
        selectedPOICategory = category
        searchForPOI(category: category)
    }
    
    private func clearPOIFilter() {
        selectedPOICategory = nil
        poiResults = []
        searchResults = []
        showingSearchResults = false
    }
    
    private func searchForPOI(category: MKPointOfInterestCategory) {
        let request = MKLocalSearch.Request()
        request.region = locationManager.region
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                if let response = response {
                    self.searchResults = response.mapItems
                    self.showingSearchResults = true
                } else {
                    self.searchResults = []
                    self.showingSearchResults = false
                }
            }
        }
    }
    
    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        // Clear suggestions immediately to prevent UI glitches
        searchSuggestions = []
        showingFavorites = false
        showingSearchResults = false

        let request = MKLocalSearch.Request(completion: suggestion)
        request.region = locationManager.region
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                if let item = response?.mapItems.first {
                    // Set the selected place first, then update searchText
                    // This prevents the onChange from triggering the completer
                    self.selectedPlace = item
                    self.searchText = item.name ?? suggestion.title
                    // Ensure all overlays are hidden
                    self.searchResults = []
                    self.showingSearchResults = false
                    self.searchSuggestions = []
                } else {
                    // Fallback: run a normal text search
                    self.searchText = suggestion.title
                    self.searchForPlaces()
                }
            }
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
        searchSuggestions = []
        showingSearchResults = false
        showingFavorites = false
        selectedPOICategory = nil
        poiResults = []
        selectedPlace = nil
    }
}

struct FavoriteRow: View {
    let favorite: FavoritePlaceModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: iconForFavorite(favorite.name))
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let address = favorite.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForFavorite(_ name: String) -> String {
        switch name.lowercased() {
        case "home":
            return "house.fill"
        case "work":
            return "briefcase.fill"
        case "school":
            return "graduationcap.fill"
        default:
            return "star.fill"
        }
    }
}
