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

    var body: some View {
        ZStack {
            MapViewContainer(
                locationManager: locationManager,
                mapType: selectedMapType,
                searchResults: searchResults,
                selectedPlace: selectedPlace,
                currentRoute: currentRoute,
                userTrackingMode: $userTrackingMode
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search for a place or address", text: $searchText)
                            .onSubmit {
                                searchForPlaces()
                            }
                            .onTapGesture {
                                if !favoritesManager.favorites.isEmpty {
                                    showingFavorites = true
                                    showingSearchResults = false
                                }
                            }
                            .onChange(of: searchText) { newValue in
                                if newValue.isEmpty {
                                    showingSearchResults = false
                                    showingFavorites = false
                                    searchResults = []
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                                selectedPlace = nil
                                showingSearchResults = false
                                showingFavorites = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .cornerRadius(22)
                            .shadow(radius: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
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
            
            if showingSearchResults && !searchResults.isEmpty {
                VStack {
                    Spacer()
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults, id: \.self) { item in
                                SearchResultRow(item: item) {
                                    selectedPlace = item
                                    showingSearchResults = false
                                    showingFavorites = false
                                    searchText = item.name ?? ""
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 5)
                    .padding(.horizontal)
                }
            }
            
            if let place = selectedPlace, !showingSearchResults && !showingFavorites {
                VStack {
                    Spacer()
                    
                    PlaceInfoCard(
                        place: place,
                        onClose: {
                            selectedPlace = nil
                            currentRoute = nil
                        },
                        onDirections: {
                            showingDirections = true
                        },
                        onFavoriteToggle: {
                            favoritesManager.toggleFavorite(place)
                        },
                        isFavorite: favoritesManager.isFavorite(place)
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 50)
                }
            }
        }
        .sheet(isPresented: $showingDirections) {
            if let place = selectedPlace {
                DirectionsView(
                    destination: place,
                    locationManager: locationManager
                ) { route in
                    currentRoute = route
                    showingDirections = false
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            locationManager.requestLocationPermission()
        }
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
