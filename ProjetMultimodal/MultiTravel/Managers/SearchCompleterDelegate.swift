import Foundation
import MapKit

class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    let onUpdate: ([MKLocalSearchCompletion]) -> Void
    
    init(onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void) {
        self.onUpdate = onUpdate
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        if Thread.isMainThread {
            onUpdate(completer.results)
        } else {
            DispatchQueue.main.async {
                self.onUpdate(completer.results)
            }
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
        if Thread.isMainThread {
            onUpdate([])
        } else {
            DispatchQueue.main.async {
                self.onUpdate([])
            }
        }
    }
}
