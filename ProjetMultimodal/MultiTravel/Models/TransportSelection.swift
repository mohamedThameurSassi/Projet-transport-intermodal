import Foundation

class TransportSelection: ObservableObject {
    @Published var selectedPreferredType: PreferredTransportType = .car
    
    func selectPreferred(_ type: PreferredTransportType) {
        selectedPreferredType = type
    }
    
    func isSelected(_ type: PreferredTransportType) -> Bool {
        return selectedPreferredType == type
    }
}
