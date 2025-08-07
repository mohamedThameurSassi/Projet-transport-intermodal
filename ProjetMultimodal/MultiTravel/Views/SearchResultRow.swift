import SwiftUI
import MapKit

// MARK: - Enhanced Search Result Row
struct SearchResultRow: View {
    let item: MKMapItem
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Location Icon with background
                ZStack {
                    Circle()
                        .fill(locationIconColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: locationIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(locationIconColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown Place")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Distance and category info
                    HStack(spacing: 12) {
                        if let category = placeCategory {
                            Label(category, systemImage: "tag.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(locationIconColor)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        // You could add distance here if you have user location
                        // Text("0.5 km")
                        //     .font(.caption)
                        //     .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                // Arrow with animation
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                    .scaleEffect(isPressed ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: .black.opacity(isPressed ? 0.15 : 0.05),
                        radius: isPressed ? 8 : 4,
                        x: 0,
                        y: isPressed ? 4 : 2
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
    
    // Determine icon based on place type
    private var locationIcon: String {
        guard let category = item.pointOfInterestCategory else {
            return "location.fill"
        }
        
        switch category {
        case .restaurant, .foodMarket, .bakery, .brewery, .cafe, .winery:
            return "fork.knife"
        case .gasStation:
            return "fuelpump.fill"
        case .hospital:
            return "cross.case.fill"
        case .pharmacy:
            return "pills.fill"
        case .hotel:
            return "bed.double.fill"
        case .store:
            return "bag.fill"
        case .school, .university:
            return "graduationcap.fill"
        case .bank:
            return "banknote.fill"
        case .parking:
            return "car.fill"
        case .publicTransport:
            return "bus.fill"
        case .park:
            return "tree.fill"
        case .museum:
            return "building.columns.fill"
        case .library:
            return "books.vertical.fill"
        default:
            return "location.fill"
        }
    }
    
    // Color based on place type
    private var locationIconColor: Color {
        guard let category = item.pointOfInterestCategory else {
            return .blue
        }
        
        switch category {
        case .restaurant, .foodMarket, .bakery, .brewery, .cafe, .winery:
            return .orange
        case .gasStation:
            return .green
        case .hospital:
            return .red
        case .pharmacy:
            return .pink
        case .hotel:
            return .purple
        case .store:
            return .blue
        case .school, .university:
            return .indigo
        case .bank:
            return .green
        case .parking:
            return .gray
        case .publicTransport:
            return .mint
        case .park:
            return .green
        case .museum:
            return .brown
        case .library:
            return .blue
        default:
            return .blue
        }
    }
    
    // Human readable category
    private var placeCategory: String? {
        guard let category = item.pointOfInterestCategory else {
            return nil
        }
        
        switch category {
        case .restaurant:
            return "Restaurant"
        case .cafe:
            return "Café"
        case .bakery:
            return "Bakery"
        case .brewery:
            return "Brewery"
        case .winery:
            return "Winery"
        case .foodMarket:
            return "Market"
        case .gasStation:
            return "Gas Station"
        case .hospital:
            return "Hospital"
        case .pharmacy:
            return "Pharmacy"
        case .hotel:
            return "Hotel"
        case .store:
            return "Store"
        case .school:
            return "School"
        case .university:
            return "University"
        case .bank:
            return "Bank"
        case .parking:
            return "Parking"
        case .publicTransport:
            return "Transit"
        case .park:
            return "Park"
        case .museum:
            return "Museum"
        case .library:
            return "Library"
        default:
            return "Place"
        }
    }
}
