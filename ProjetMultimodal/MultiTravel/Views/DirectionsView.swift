import SwiftUI
import MapKit

// MARK: - Directions View (Legacy - redirects to HealthTripPlannerView)
struct DirectionsView: View {
    let destination: MKMapItem
    let locationManager: LocationManager
    let onRouteCalculated: (MKRoute) -> Void
    var onHealthRouteSelected: ((TripResponse.RouteOption) -> Void)? = nil
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        HealthTripPlannerView(
            destination: destination,
            locationManager: locationManager
        ) { routeOption in
            onHealthRouteSelected?(routeOption)
            presentationMode.wrappedValue.dismiss()
        }
    }
}
