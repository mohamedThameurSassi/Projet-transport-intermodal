import SwiftUI
import MapKit

// MARK: - Directions View (Legacy - redirects to HealthTripPlannerView)
struct DirectionsView: View {
    let destination: MKMapItem
    let locationManager: LocationManager
    let onRouteCalculated: (MKRoute) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        HealthTripPlannerView(
            destination: destination,
            locationManager: locationManager
        ) { routeOption in
            // For legacy compatibility, we'll just dismiss
            // In a full implementation, you'd convert the route option to MKRoute
            presentationMode.wrappedValue.dismiss()
        }
    }
}
