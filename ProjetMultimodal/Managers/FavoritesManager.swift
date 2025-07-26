import Foundation
import MapKit

class FavoritesManager: ObservableObject {
    @Published var favorites: [FavoritePlaceModel] = []
    
    private let userDefaults = UserDefaults.standard
    private let favoritesKey = "FavoritePlaces"
    
    init() {
        loadFavorites()
    }
    
    func addFavorite(_ place: MKMapItem) {
        let favoritePlace = FavoritePlaceModel(from: place)
        favorites.append(favoritePlace)
        saveFavorites()
    }
    
    func removeFavorite(_ place: MKMapItem) {
        favorites.removeAll { favorite in
            favorite.coordinate.latitude == place.placemark.coordinate.latitude &&
            favorite.coordinate.longitude == place.placemark.coordinate.longitude
        }
        saveFavorites()
    }
    
    func isFavorite(_ place: MKMapItem) -> Bool {
        return favorites.contains { favorite in
            favorite.coordinate.latitude == place.placemark.coordinate.latitude &&
            favorite.coordinate.longitude == place.placemark.coordinate.longitude
        }
    }
    
    func toggleFavorite(_ place: MKMapItem) {
        if isFavorite(place) {
            removeFavorite(place)
        } else {
            addFavorite(place)
        }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            userDefaults.set(encoded, forKey: favoritesKey)
        }
    }
    
    private func loadFavorites() {
        if let data = userDefaults.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoritePlaceModel].self, from: data) {
            favorites = decoded
        }
    }
}
