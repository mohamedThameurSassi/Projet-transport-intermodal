import SwiftUI
import MapKit

struct PlaceInfoCard: View {
    let place: MKMapItem
    let onClose: () -> Void
    let onDirections: () -> Void
    let onCarWalkDirections: () -> Void
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
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onDirections) {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                .font(.system(size: 14, weight: .medium))
                            Text("Directions")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    Button(action: onCarWalkDirections) {
                        HStack {
                            Image(systemName: "car.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text("+")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "figure.walk")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.green, .mint]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                
                Text("🚗 + 🚶 Get healthier route with parking and walking")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
