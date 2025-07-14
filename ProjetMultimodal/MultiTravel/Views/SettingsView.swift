import SwiftUI
import MapKit

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var favoritesManager = FavoritesManager()
    @State private var showingAddFavorite = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Favorites") {
                    if favoritesManager.favorites.isEmpty {
                        Text("No favorites yet")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(favoritesManager.favorites, id: \.id) { favorite in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.name)
                                        .font(.headline)
                                    
                                    if let address = favorite.address, !address.isEmpty {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    removeFavorite(favorite)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button(action: {
                        showingAddFavorite = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add Favorite Place")
                        }
                    }
                }
                
                Section("Map Preferences") {
                    HStack {
                        Text("Avoid Tolls")
                        Spacer()
                        Toggle("", isOn: .constant(false))
                    }
                    
                    HStack {
                        Text("Avoid Highways")
                        Spacer()
                        Toggle("", isOn: .constant(false))
                    }
                }
                
                Section("Voice & Sound") {
                    HStack {
                        Text("Voice Volume")
                        Spacer()
                        Text("Medium")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddFavorite) {
            AddFavoriteView(favoritesManager: favoritesManager)
        }
    }
    
    private func removeFavorite(_ favorite: FavoritePlaceModel) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: favorite.coordinate.latitude,
            longitude: favorite.coordinate.longitude
        ))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = favorite.name
        
        favoritesManager.toggleFavorite(mapItem)
    }
}

struct AddFavoriteView: View {
    let favoritesManager: FavoritesManager
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var isSettingQuickAdd = false
    @State private var selectedQuickAddType: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField(isSettingQuickAdd ? "Search for your \(selectedQuickAddType?.lowercased() ?? "place")" : "Search for a place to add", text: $searchText)
                        .onSubmit {
                            searchForPlaces()
                        }
                        .onChange(of: searchText) { _ in
                            if searchText.isEmpty {
                                searchResults = []
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Quick Actions
                VStack(spacing: 12) {
                    Text("Quick Add")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        QuickAddButton(title: "Home", icon: "house.fill") {
                            startQuickAddSetup(type: "Home")
                        }
                        
                        QuickAddButton(title: "Work", icon: "briefcase.fill") {
                            startQuickAddSetup(type: "Work")
                        }
                        
                        QuickAddButton(title: "School", icon: "graduationcap.fill") {
                            startQuickAddSetup(type: "School")
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
                
                if isSettingQuickAdd {
                    HStack {
                        Text("Setting address for \(selectedQuickAddType ?? "")")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Spacer()
                        Button("Cancel") {
                            cancelQuickAddSetup()
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                    .padding(.vertical)
                
                // Search Results
                if isSearching {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Text("No results found")
                        .foregroundColor(.gray)
                        .padding()
                } else if !searchResults.isEmpty {
                    List(searchResults, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Unknown Place")
                                .font(.headline)
                            
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSettingQuickAdd {
                                addQuickAddFavorite(item)
                            } else {
                                addToFavorites(item)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Add Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startQuickAddSetup(type: String) {
        selectedQuickAddType = type
        isSettingQuickAdd = true
        searchText = ""
        searchResults = []
    }
    
    private func cancelQuickAddSetup() {
        isSettingQuickAdd = false
        selectedQuickAddType = nil
        searchText = ""
        searchResults = []
    }
    
    private func addQuickAddFavorite(_ item: MKMapItem) {
        let placemark = MKPlacemark(coordinate: item.placemark.coordinate)
        let customItem = MKMapItem(placemark: placemark)
        customItem.name = selectedQuickAddType
        
        favoritesManager.addFavorite(customItem)
        dismiss()
    }
    
    private func searchForPlaces() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false
                
                guard let response = response else { return }
                self.searchResults = response.mapItems
            }
        }
    }
    
    private func addToFavorites(_ item: MKMapItem) {
        favoritesManager.addFavorite(item)
        dismiss()
    }
}

struct QuickAddButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
