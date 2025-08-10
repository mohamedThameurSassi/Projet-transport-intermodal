import SwiftUI
import MapKit

// MARK: - Place Info Card (aligned with MultiTravel version)
struct PlaceInfoCard: View {
    let place: MKMapItem
    let onClose: () -> Void
    let onDirections: () -> Void
    let onCarWalkDirections: () -> Void
    let onFavoriteToggle: () -> Void
    let isFavorite: Bool
    let onGo: () -> Void
    let isStartingNavigation: Bool
    
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
                // Primary Go button
                Button(action: onGo) {
                    HStack {
                        if isStartingNavigation {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isStartingNavigation ? "Starting..." : "Go")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isStartingNavigation)
                
                // Secondary options row
                HStack(spacing: 8) {
                    Button(action: onDirections) {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                .font(.system(size: 12, weight: .medium))
                            Text("Plan")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                    
                    Button(action: onCarWalkDirections) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 12, weight: .medium))
                            Text("Park & Walk")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
