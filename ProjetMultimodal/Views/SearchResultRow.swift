import SwiftUI
import MapKit

// MARK: - Search Result Row
struct SearchResultRow: View {
    let item: MKMapItem
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown Place")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}