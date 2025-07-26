import SwiftUI
import MapKit

// MARK: - Place Info Card
struct PlaceInfoCard: View {
    let place: MKMapItem
    let onClose: () -> Void
    let onDirections: () -> Void
    let onFavoriteToggle: () -> Void
    let isFavorite: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "Unknown Place")
                        .font(.headline)
                    
                    if let address = place.placemark.title {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onFavoriteToggle) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : .gray)
                    }
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            HStack(spacing: 16) {
                Button(action: onDirections) {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        Text("Directions")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                }) {
                    HStack {
                        Image(systemName: "phone")
                        Text("Call")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
