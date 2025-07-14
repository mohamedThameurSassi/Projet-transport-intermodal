import Foundation

class TransportSelection: ObservableObject {
    @Published var selectedTypes: Set<TransportType> = [.automobile]
    
    func toggle(_ type: TransportType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
        
        if selectedTypes.isEmpty {
            selectedTypes.insert(.automobile)
        }
    }
    
    func isSelected(_ type: TransportType) -> Bool {
        return selectedTypes.contains(type)
    }
    
    var selectedTypesArray: [TransportType] {
        return Array(selectedTypes).sorted { $0.rawValue < $1.rawValue }
    }
}
