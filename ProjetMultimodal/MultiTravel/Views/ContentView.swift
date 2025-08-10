import SwiftUI
import MapKit

struct ContentView: View {
    @AppStorage("walkingObjective") private var walkingObjective: Int = 30
    @AppStorage("activity.weeklyMinutes") private var weeklyMinutes: Int = 0
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
    @State private var showingProfile = false
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var isStartingNavigation = false

    @State private var showingCarWalkPlanner = false
    @State private var currentCarWalkRoute: CarWalkRouteResponse?

    @State private var selectedHealthRoute: TripResponse.RouteOption?
    @State private var healthOverlays: [HealthSegmentOverlay] = []
    @State private var activeHealthSegmentIndex: Int? = nil

    @State private var searchCompleter = MKLocalSearchCompleter()
    @State private var searchSuggestions: [MKLocalSearchCompletion] = []
    @State private var selectedPOICategory: MKPointOfInterestCategory?
    @State private var poiResults: [MKMapItem] = []
    @State private var completerDelegate: SearchCompleterDelegate?

    // Take a walk feature
    @State private var showingWalkSheet = false
    @State private var walkMinutes: Double = 15
    @State private var walkPOIResults: [MKMapItem] = []
    @State private var isWalkFiltering: Bool = false
    // Walking trip quick-start
    @State private var pendingWalkingStart = false
    @FocusState private var searchFieldFocused: Bool
    // ETA filtering control
    @State private var etaFilterRunId: Int = 0
    @State private var ongoingDirections: [MKDirections] = []

    // Use POI results for map if a POI filter is active, else use searchResults
    private var mapResults: [MKMapItem] {
        if selectedPOICategory != nil { return poiResults }
        return searchResults
    }

    var body: some View {
        ZStack {
            
            if currentCarWalkRoute != nil || !healthOverlays.isEmpty {
                EnhancedMapViewContainer(
                    locationManager: locationManager,
                    mapType: selectedMapType,
                    searchResults: mapResults,
                    selectedPlace: selectedPlace,
                    carWalkRoute: currentCarWalkRoute,
                    healthOverlays: healthOverlays.isEmpty ? nil : healthOverlays,
                    activeHealthSegmentIndex: activeHealthSegmentIndex,
                    userTrackingMode: $userTrackingMode
                )
                .ignoresSafeArea()
            } else {
                MapViewContainer(
                    locationManager: locationManager,
                    mapType: selectedMapType,
                    searchResults: mapResults,
                    selectedPlace: selectedPlace,
                    currentRoute: currentRoute,
                    userTrackingMode: $userTrackingMode
                )
                .ignoresSafeArea()
            }

            // Top controls & overlays
            VStack {
                // Search + Settings row
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(searchText.isEmpty ? .gray : .blue)
                            .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)

                        TextField("Where would you like to go?", text: $searchText)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .focused($searchFieldFocused)
                            .onSubmit { searchForPlaces() }
                            .onTapGesture {
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
                                } else if selectedPlace == nil {
                                    searchCompleter.queryFragment = newValue
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
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )

                    Button(action: { showingProfile = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            )
                    }
                    .shadow(radius: 2)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                // POI filter
                if !searchText.isEmpty || selectedPOICategory != nil {
                    poiFilterButtons
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Right-side utility buttons + floating Take a walk
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
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
                            Button("Standard") { selectedMapType = .standard }
                            Button("Satellite") { selectedMapType = .satellite }
                            Button("Hybrid") { selectedMapType = .hybrid }
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
                            Button(action: { showingDirections = true }) {
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
                .padding(.bottom, 36)

                Spacer()
            }

           
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Button(action: {
                                                    walkMinutes = Double(walkingObjective)
                                                    showingWalkSheet = true
                                                }) {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: "figure.walk")
                                                        Text("Take a walk")
                                                    }
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(Color.green.opacity(0.95))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(20)
                                                    .shadow(radius: 3)
                                                }
                                                .padding(.leading, 20)
                                                Spacer()
                                            }
                                            .padding(.bottom, 36)
                                        }
            if !walkPOIResults.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text("POIs at least \(Int(walkMinutes)) min away")
                            .font(.headline)
                            .padding(.leading)
                        Spacer()
                        Button("Clear") {
                            walkPOIResults = []
                            searchResults = []
                            showingSearchResults = false
                        }
                        .padding(.trailing)
                        .disabled(isWalkFiltering)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(walkPOIResults, id: \.self) { item in
                                SearchResultRow(item: item) {
                                    selectedPlace = item
                                    walkPOIResults = []
                                }
                                .frame(width: 220)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 10)
                    if isWalkFiltering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            
            if showingFavorites && !favoritesManager.favorites.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 0) {
                        HStack {
                            Text("Favorites")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: { showingFavorites = false }) {
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

            
            if (showingSearchResults && !searchResults.isEmpty && selectedPlace == nil)
                || (!searchSuggestions.isEmpty && !searchText.isEmpty && selectedPlace == nil) {
                VStack {
                    Spacer()
                    VStack(spacing: 0) {
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

                        Divider().background(Color(.systemGray4))

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if !searchSuggestions.isEmpty && !searchText.isEmpty && searchResults.isEmpty {
                                    ForEach(searchSuggestions, id: \.title) { suggestion in
                                        SearchSuggestionRow(suggestion: suggestion) {
                                            selectSuggestion(suggestion)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }

                                ForEach(searchResults, id: \.self) { item in
                                    SearchResultRow(item: item) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedPlace = item
                                            searchText = item.name ?? ""
                                            showingSearchResults = false
                                            showingFavorites = false
                                            searchSuggestions = []
                                            searchResults = []
                                        }
                                        if pendingWalkingStart, let dest = selectedPlace {
                                            startWalkingTrip(to: dest)
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
                            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -8)
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            
            if let place = selectedPlace,
               !showingSearchResults, !showingFavorites,
               selectedHealthRoute == nil, currentCarWalkRoute == nil {
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
                        onDirections: { showingDirections = true },
                        onCarWalkDirections: { showingCarWalkPlanner = true },
                        onFavoriteToggle: { favoritesManager.toggleFavorite(place) },
                        isFavorite: favoritesManager.isFavorite(place),
                        onGo: {
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

            
            if let route = selectedHealthRoute,
               let idx = activeHealthSegmentIndex,
               route.segments.indices.contains(idx) {
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

                VStack {
                    NavigationHUD(
                        segment: route.segments[idx],
                        index: idx,
                        total: route.segments.count,
                        onEnd: { endHealthTripAndCreditMinutes() }
                    )
                    Spacer()
                }
                .padding(.top, 12)
                .transition(.opacity)
            }

            
            if currentRoute != nil && selectedHealthRoute == nil && currentCarWalkRoute == nil {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.green))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Walking trip in progress")
                                .font(.headline)
                                .foregroundColor(.white)
                            if let name = selectedPlace?.name {
                                Text("To \(name)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        Spacer()
                        Button(action: { endWalkingTripAndCreditMinutes() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                Text("End")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.red.opacity(0.95)))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Sheets are attached to the outer ZStack to avoid brace/paren confusion
        .sheet(isPresented: $showingWalkSheet) {
            VStack(spacing: 32) {
                Text("How far do you want to walk?")
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack {
                    Text("0")
                    Slider(value: $walkMinutes, in: 5...60, step: 1)
                    Text("60 min")
                }
                Text("\(Int(walkMinutes)) minutes")
                    .font(.headline)
                Button("OK") {
                    showingWalkSheet = false
                    findPOIsWithinWalk(minutes: Int(walkMinutes))
                }
                .font(.headline)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingDirections) {
            Group {
                if let place = selectedPlace {
                    DirectionsView(
                        destination: place,
                        locationManager: locationManager
                    ) { route in
                        currentRoute = route
                        currentCarWalkRoute = nil
                        showingDirections = false
                    } onHealthRouteSelected: { option in
                        Task { await startHealthFollow(with: option) }
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingCarWalkPlanner) {
            Group {
                if let place = selectedPlace {
                    CarWalkPlannerView(
                        destination: place,
                        locationManager: locationManager
                    ) { carWalkRoute in
                        currentCarWalkRoute = carWalkRoute
                        currentRoute = nil
                        selectedHealthRoute = nil
                        healthOverlays = []
                        activeHealthSegmentIndex = nil
                        showingCarWalkPlanner = false
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .onAppear {
            locationManager.requestLocationPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                locationManager.ensureProperRegion()
            }
            setupSearchCompleter()
        }
    }

    // MARK: - Follow mode helpers
    private func startHealthFollow(with option: TripResponse.RouteOption) async {
        currentRoute = nil
        currentCarWalkRoute = nil
        selectedPlace = nil

        let mkRoutes = await HealthTripService().computeMKRoutes(for: option)

        await MainActor.run {
            self.selectedHealthRoute = option
            self.healthOverlays = mkRoutes.enumerated().map { idx, route in
                HealthSegmentOverlay(polyline: route.polyline,
                                     mode: option.segments[idx].transportType)
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

    
    private func endHealthTripAndCreditMinutes() {
        if let route = selectedHealthRoute {
            
            let walkingSeconds = route.segments
                .filter { $0.transportType == .walking }
                .map { $0.duration }
                .reduce(0, +)
            let mins = max(0, Int((walkingSeconds / 60.0).rounded()))
            weeklyMinutes += mins
        }
        clearHealthFollow()
    }

    // MARK: - Search logic
    private func searchForPlaces() {
        guard !searchText.isEmpty else { return }
        showingFavorites = false

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = locationManager.region

        MKLocalSearch(request: request).start { response, _ in
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
        if pendingWalkingStart {
            startWalkingTrip(to: mapItem)
        }
    }

    // MARK: - POI Filter Buttons
    private var poiFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                POIFilterButton(
                    icon: "location.fill",
                    title: "All",
                    color: .blue,
                    isSelected: selectedPOICategory == nil
                ) { clearPOIFilter() }

                POIFilterButton(
                    icon: "fork.knife",
                    title: "Restaurants",
                    color: .orange,
                    isSelected: selectedPOICategory == .restaurant
                ) { filterPOI(.restaurant) }

                POIFilterButton(
                    icon: "fuelpump.fill",
                    title: "Gas",
                    color: .green,
                    isSelected: selectedPOICategory == .gasStation
                ) { filterPOI(.gasStation) }

                POIFilterButton(
                    icon: "cross.case.fill",
                    title: "Hospital",
                    color: .red,
                    isSelected: selectedPOICategory == .hospital
                ) { filterPOI(.hospital) }

                POIFilterButton(
                    icon: "pills.fill",
                    title: "Pharmacy",
                    color: .pink,
                    isSelected: selectedPOICategory == .pharmacy
                ) { filterPOI(.pharmacy) }

                POIFilterButton(
                    icon: "bag.fill",
                    title: "Stores",
                    color: .blue,
                    isSelected: selectedPOICategory == .store
                ) { filterPOI(.store) }

                POIFilterButton(
                    icon: "bus.fill",
                    title: "Transit",
                    color: .mint,
                    isSelected: selectedPOICategory == .publicTransport
                ) { filterPOI(.publicTransport) }
            }
            .padding(.horizontal, 20)
        }
    }

    private func setupSearchCompleter() {
        completerDelegate = SearchCompleterDelegate { suggestions in
            DispatchQueue.main.async {
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
        // Use MKLocalPointsOfInterestRequest for POI search
        let center = locationManager.region.center
        let radius = min(locationManager.region.span.latitudeDelta, locationManager.region.span.longitudeDelta) * 111_000 / 2 // rough meters
        let poiRequest = MKLocalPointsOfInterestRequest(center: center, radius: max(500, radius))
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])

    MKLocalSearch(request: poiRequest).start { response, _ in
            DispatchQueue.main.async {
                if let response = response {
                    self.poiResults = response.mapItems
                    self.searchResults = response.mapItems
                    self.showingSearchResults = true
                } else {
                    self.poiResults = []
                    self.searchResults = []
                    self.showingSearchResults = false
                }
            }
        }
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        searchSuggestions = []
        showingFavorites = false
        showingSearchResults = false

        let request = MKLocalSearch.Request(completion: suggestion)
        request.region = locationManager.region

        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                if let item = response?.mapItems.first {
                    self.selectedPlace = item
                    self.searchText = item.name ?? suggestion.title
                    self.searchResults = []
                    self.showingSearchResults = false
                    self.searchSuggestions = []
                    if self.pendingWalkingStart {
                        self.startWalkingTrip(to: item)
                    }
                } else {
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
    pendingWalkingStart = false
    }

    // MARK: - Take a walk
    private func findPOIsWithinWalk(minutes: Int) {
        
        let userCoord: CLLocationCoordinate2D
        let hasAccurateUserLoc: Bool
        if let last = locationManager.lastLocation {
            userCoord = last.coordinate
            hasAccurateUserLoc = true
        } else {
            userCoord = locationManager.region.center
            hasAccurateUserLoc = false
        }

        let walkSpeedMetersPerMin = 80.0 // ~4.8km/h
        let baseRadius = Double(minutes) * walkSpeedMetersPerMin
        
        let radius = max(300, baseRadius * 2.0)

        
        let poiRequest = MKLocalPointsOfInterestRequest(center: userCoord, radius: max(200, radius))
        

        
        ongoingDirections.forEach { $0.cancel() }
        ongoingDirections.removeAll()
        etaFilterRunId &+= 1
        isWalkFiltering = true

    MKLocalSearch(request: poiRequest).start { response, _ in
            DispatchQueue.main.async {
                let items = response?.mapItems ?? []

                
                self.currentRoute = nil
                self.currentCarWalkRoute = nil
                self.selectedHealthRoute = nil
                self.healthOverlays = []
                self.activeHealthSegmentIndex = nil
                self.showingFavorites = false
                self.selectedPlace = nil
                self.showingSearchResults = false

                
                self.walkPOIResults = items
                self.searchResults = items

                
                let region = MKCoordinateRegion(center: userCoord, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
                self.locationManager.region = region

                
                guard hasAccurateUserLoc, !items.isEmpty else {
                    self.isWalkFiltering = false
                    return
                }

                
                self.filterPOIsByWalkingETA(items: items, minutes: minutes, atLeast: true)
            }
        }
    }

    
    private func filterPOIsByWalkingETA(items: [MKMapItem], minutes: Int, atLeast: Bool) {
        guard let userLocation = locationManager.lastLocation else {
            
            self.walkPOIResults = items
            self.searchResults = items
            self.isWalkFiltering = false
            return
        }
        let source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        let threshold: TimeInterval = TimeInterval(minutes * 60)
        let metersPerMinute = 80.0
        let thresholdDistance = metersPerMinute * Double(minutes)

        
        let candidates = items
            .filter { item in
                let d = CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
                    .distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                // We're looking for at least N minutes away; drop obviously closer items
                return d >= thresholdDistance * 0.9 // small cushion
            }
            .sorted { a, b in
                let da = CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
                    .distance(from: CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude))
                let db = CLLocation(latitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude)
                    .distance(from: CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude))
                return da < db
            }

        
        let maxRequests = 8
        let list = Array(candidates.prefix(maxRequests))

        var kept: [(MKMapItem, TimeInterval)] = []
        let currentRunId = etaFilterRunId

    func process(index: Int) {
            
            if currentRunId != etaFilterRunId { return }
            if index >= list.count {
                
                if currentRunId == etaFilterRunId {
            let sorted = kept.sorted(by: { $0.1 < $1.1 }).map { $0.0 }
            // Fallback: if nothing met the threshold, keep the nearest few so the user sees POIs
            let final = sorted.isEmpty ? list : sorted
            self.walkPOIResults = final
            self.searchResults = final
            self.isWalkFiltering = false
                }
                return
            }

            let item = list[index]
            let req = MKDirections.Request()
            req.source = source
            req.destination = item
            req.transportType = .walking
            req.requestsAlternateRoutes = false

            let directions = MKDirections(request: req)
            self.ongoingDirections.append(directions)
            directions.calculateETA { etaResp, _ in
                // Remove from ongoing
                if let i = self.ongoingDirections.firstIndex(where: { $0 === directions }) {
                    self.ongoingDirections.remove(at: i)
                }
                if let eta = etaResp?.expectedTravelTime {
                    let pass = atLeast ? (eta >= threshold) : (eta <= threshold)
                    if pass { kept.append((item, eta)) }
                    
                    let interim = kept.sorted(by: { $0.1 < $1.1 }).map { $0.0 }
                    if currentRunId == etaFilterRunId {
                        self.walkPOIResults = interim.isEmpty ? self.walkPOIResults : interim
                        self.searchResults = interim.isEmpty ? self.searchResults : interim
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    process(index: index + 1)
                }
            }
        }

        process(index: 0)
    }

    // MARK: - Start walking trip
    private func startWalkingTrip(to destination: MKMapItem) {
        pendingWalkingStart = false
        showingFavorites = false
        showingSearchResults = false
        
        guard let userLocation = locationManager.lastLocation else { return }
        let sourcePlacemark = MKPlacemark(coordinate: userLocation.coordinate)
        let source = MKMapItem(placemark: sourcePlacemark)

        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        MKDirections(request: request).calculate { response, error in
            guard let route = response?.routes.first else { return }
            DispatchQueue.main.async {
                self.currentRoute = route
                self.selectedPlace = destination
                self.currentCarWalkRoute = nil
                self.selectedHealthRoute = nil
                self.healthOverlays = []
                self.activeHealthSegmentIndex = nil
                
            }
        }
    }

    
    private func endWalkingTripAndCreditMinutes() {
        guard let route = currentRoute else { return }
        let mins = max(0, Int((route.expectedTravelTime / 60.0).rounded()))
        weeklyMinutes += mins
        // Clear the active route and selection
        currentRoute = nil
        selectedPlace = nil
    }
}

// MARK: - Favorite row
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
        case "home": return "house.fill"
        case "work": return "briefcase.fill"
        case "school": return "graduationcap.fill"
        default: return "star.fill"
        }
    }
}
