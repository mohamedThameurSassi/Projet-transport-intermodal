import Foundation
import CoreLocation
import MapKit

class HealthTripService: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: TripResponse?
    @Published var error: String?
    
    private let baseURL = "http://localhost:8080"
    private let session = URLSession.shared
    
    func requestHealthyAlternatives(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        originAddress: String?,
        destinationAddress: String?,
        preferredTransport: PreferredTransportType,
        exerciseMinutes: Double,
        exerciseType: HealthTransportType
    ) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        let originalOption: TripResponse.RouteOption
        do {
            originalOption = try await computeMKOriginalRoute(
                origin: origin,
                destination: destination,
                preferredTransport: preferredTransport
            )
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
            return
        }

        let req = TripRequest(
            origin: TripRequest.LocationPoint(
                latitude: origin.latitude,
                longitude: origin.longitude,
                address: originAddress
            ),
            destination: TripRequest.LocationPoint(
                latitude: destination.latitude,
                longitude: destination.longitude,
                address: destinationAddress
            ),
            preferredTransport: preferredTransport.serverValue,
            requestTime: Date()
        )

        var alternatives: [TripResponse.RouteOption] = []
        var reqId = "local_\(Int(Date().timeIntervalSince1970))"

    if preferredTransport == .car {
            do {
        let alt = try await requestCarWalkAlternative(origin: origin, destination: destination, walkDurationMinutes: exerciseMinutes)
                alternatives = [alt]
            } catch {
            }
        } else {
            do {
        let alt = try await requestTransitAlternative(origin: origin, destination: destination, maxWalkMinutes: exerciseMinutes)
                alternatives = [alt]
            } catch {
            }
        }

        let combined = TripResponse(
            originalRoute: originalOption,
            healthAlternatives: alternatives,
            requestId: reqId
        )

        await MainActor.run {
            self.lastResponse = combined
            self.isLoading = false
            if combined.originalRoute.totalDuration == 0 && combined.healthAlternatives.isEmpty {
                self.error = self.error ?? "Couldn't compute route"
            }
        }
    }
    
    private func sendTripRequest(_ request: TripRequest) async throws -> TripResponse {
        guard let url = URL(string: "\(baseURL)/api/health-route") else {
            throw TripServiceError.invalidURL
        }
        
    var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonData = try encoder.encode(request)
        urlRequest.httpBody = jsonData
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw TripServiceError.serverError
        }
        
        let decoder = JSONDecoder()
        do {
            let tripResponse = try decoder.decode(TripResponse.self, from: data)
            return tripResponse
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("HealthTripService decode error: \(error)\nResponse body: \n\(body)")
            #endif
            throw TripServiceError.decodingError
        }
    }
}

extension HealthTripService {
    private func requestCarWalkAlternative(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        walkDurationMinutes: Double
    ) async throws -> TripResponse.RouteOption {
        struct Req: Codable { let startLat, startLon, endLat, endLon, walkDurationMins: Double }
        guard let url = URL(string: "\(baseURL)/route/car-walk") else { throw TripServiceError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = Req(
            startLat: origin.latitude,
            startLon: origin.longitude,
            endLat: destination.latitude,
            endLon: destination.longitude,
            walkDurationMins: walkDurationMinutes
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw TripServiceError.serverError
        }

        struct Step: Codable {
            let mode: String
            let fromCoord: Coord
            let toCoord: Coord
            let durationSec: Double
            let distanceM: Double
            let description: String
            enum CodingKeys: String, CodingKey { case mode = "Mode", fromCoord = "FromCoord", toCoord = "ToCoord", durationSec = "DurationSec", distanceM = "DistanceM", description = "Description" }
        }
        struct Coord: Codable { let lat: Double; let lon: Double; enum CodingKeys: String, CodingKey { case lat = "Lat", lon = "Lon" } }
        struct Resp: Codable { let steps: [Step]; let totalDistanceM: Double; let totalDurationSec: Double; let walkDistanceM: Double; let carDistanceM: Double; let caloriesBurned: Int?; let carbonFootprintKg: Double? }
        let resp = try JSONDecoder().decode(Resp.self, from: data)

        let segments: [TripResponse.RouteOption.RouteSegment] = resp.steps.map { s in
            let t: HealthTransportType = (s.mode.lowercased() == "car") ? .driving : .walking
            let start = TripRequest.LocationPoint(latitude: s.fromCoord.lat, longitude: s.fromCoord.lon, address: nil)
            let end = TripRequest.LocationPoint(latitude: s.toCoord.lat, longitude: s.toCoord.lon, address: nil)
            return TripResponse.RouteOption.RouteSegment(
                transportType: t,
                duration: s.durationSec,
                distance: s.distanceM,
                instructions: s.description,
                startLocation: start,
                endLocation: end,
                polyline: nil
            )
        }

   
        let walkSteps = resp.steps.filter { $0.mode.lowercased() != "car" }
        let walkDurationSec = walkSteps.reduce(0.0) { $0 + $1.durationSec }
        let walkStart: Coord? = walkSteps.first?.fromCoord
        var drivingDurationSec: TimeInterval = 0
        if let ws = walkStart {
            do {
                let (time, _) = try await computeDrivingTimeSeconds(from: origin, to: CLLocationCoordinate2D(latitude: ws.lat, longitude: ws.lon))
                drivingDurationSec = time
            } catch {
                drivingDurationSec = resp.steps.filter { $0.mode.lowercased() == "car" }.reduce(0.0) { $0 + $1.durationSec }
            }
        } else {
            drivingDurationSec = resp.steps.filter { $0.mode.lowercased() == "car" }.reduce(0.0) { $0 + $1.durationSec }
        }

        let totalDuration = drivingDurationSec + walkDurationSec
        let totalDistance = resp.totalDistanceM
        let calories = resp.caloriesBurned ?? Int((resp.walkDistanceM / 1000.0) * 50.0)
        let carbon = resp.carbonFootprintKg ?? (resp.carDistanceM / 1000.0) * 0.21

        return TripResponse.RouteOption(
            id: "drive_and_walk",
            segments: segments,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            estimatedCalories: calories,
            healthScore: 6,
            carbonFootprint: carbon
        )
    }

    private func requestTransitAlternative(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        maxWalkMinutes: Double
    ) async throws -> TripResponse.RouteOption {
        struct Req: Codable { let startLat, startLon, endLat, endLon, walkDurationMins: Double }
        guard let url = URL(string: "\(baseURL)/route/transit") else { throw TripServiceError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = Req(
            startLat: origin.latitude,
            startLon: origin.longitude,
            endLat: destination.latitude,
            endLon: destination.longitude,
            walkDurationMins: maxWalkMinutes
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw TripServiceError.serverError
        }

        struct Step: Codable {
            let mode: String
            let fromCoord: Coord
            let toCoord: Coord
            let durationSec: Double
            let distanceM: Double
            let description: String
            let polyline: String? // New field for Google Maps polylines
            enum CodingKeys: String, CodingKey { 
                case mode = "Mode", fromCoord = "FromCoord", toCoord = "ToCoord", 
                     durationSec = "DurationSec", distanceM = "DistanceM", description = "Description",
                     polyline = "Polyline" 
            }
        }
        struct Coord: Codable { let lat: Double; let lon: Double; enum CodingKeys: String, CodingKey { case lat = "Lat", lon = "Lon" } }
        struct Resp: Codable { let steps: [Step]; let totalDistanceM: Double; let totalDurationSec: Double; let walkDistanceM: Double }
        let resp = try JSONDecoder().decode(Resp.self, from: data)

        let segments: [TripResponse.RouteOption.RouteSegment] = resp.steps.map { s in
            let m = s.mode.lowercased()
            let t: HealthTransportType
            if m == "transit" { t = .transit }
            else if m == "car" { t = .driving }
            else { t = .walking }
            let start = TripRequest.LocationPoint(latitude: s.fromCoord.lat, longitude: s.fromCoord.lon, address: nil)
            let end = TripRequest.LocationPoint(latitude: s.toCoord.lat, longitude: s.toCoord.lon, address: nil)
            return TripResponse.RouteOption.RouteSegment(
                transportType: t,
                duration: s.durationSec,
                distance: s.distanceM,
                instructions: s.description,
                startLocation: start,
                endLocation: end,
                polyline: s.polyline // Pass through the polyline from server
            )
        }

      
        let walkSteps = resp.steps.filter { $0.mode.lowercased() != "transit" }
        let walkDurationSec = walkSteps.reduce(0.0) { $0 + $1.durationSec }
        
        let transitSteps = resp.steps.filter { $0.mode.lowercased() == "transit" }
        let transitEnd: Coord? = transitSteps.last?.toCoord
        
        var transitDurationSec: TimeInterval = 0
        if let te = transitEnd {
            do {
                let (time, _) = try await computeTransitTimeSeconds(from: origin, to: CLLocationCoordinate2D(latitude: te.lat, longitude: te.lon))
                transitDurationSec = time
                
                let serverTransitTime = transitSteps.reduce(0.0) { $0 + $1.durationSec }
            } catch {
                print("🚌 MKDirections transit failed, using server time: \(error)")
                transitDurationSec = transitSteps.reduce(0.0) { $0 + $1.durationSec }
            }
        } else {
            transitDurationSec = transitSteps.reduce(0.0) { $0 + $1.durationSec }
        }

        let totalDuration = transitDurationSec + walkDurationSec
        let totalDistance = resp.totalDistanceM
        let calories = Int((resp.walkDistanceM / 1000.0) * 50.0)
        let transitDistanceM = max(0.0, resp.totalDistanceM - resp.walkDistanceM)
        let carbon = (transitDistanceM / 1000.0) * 0.05

        return TripResponse.RouteOption(
            id: "transit_and_walk",
            segments: segments,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            estimatedCalories: calories,
            healthScore: 7,
            carbonFootprint: carbon
        )
    }

    private func mkTransportType(for t: HealthTransportType) -> MKDirectionsTransportType {
        switch t {
        case .driving: return .automobile
        case .transit: return .transit
        case .walking, .biking: return .walking
        }
    }

    private func computeMKRouteForSegment(_ seg: TripResponse.RouteOption.RouteSegment) async throws -> MKRoute {
        let req = MKDirections.Request()
        req.source = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: seg.startLocation.latitude, longitude: seg.startLocation.longitude))
        )
        req.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: seg.endLocation.latitude, longitude: seg.endLocation.longitude))
        )
        req.transportType = mkTransportType(for: seg.transportType)
        req.requestsAlternateRoutes = false

        let mk = MKDirections(request: req)
        return try await withCheckedThrowingContinuation { cont in
            mk.calculate { resp, err in
                if let err = err { cont.resume(throwing: err); return }
                guard let route = resp?.routes.first else {
                    cont.resume(throwing: TripServiceError.serverError)
                    return
                }
                #if DEBUG
                print("\n=== MKRoute Debug: Segment \(seg.transportType.rawValue) ===")
                let totalDist = String(format: "%.1f km", route.distance / 1000.0)
                let totalDur = String(format: "%.0f s", route.expectedTravelTime)
                print("Route name: \(route.name)")
                print("Total distance: \(totalDist), Total duration: \(totalDur), stepCount=\(route.steps.count)")
                if !route.advisoryNotices.isEmpty {
                    print("Notices: \(route.advisoryNotices.joined(separator: " | "))")
                }
                for (idx, step) in route.steps.enumerated() {
                    let dist = String(format: "%.0f m", step.distance)
                    let instr = step.instructions.isEmpty ? "(no instruction)" : step.instructions
                    print(String(format: "  [%02d] %@ — %@", idx, dist, instr))
                }
                print("=== End MKRoute Debug ===\n")
                #endif
                cont.resume(returning: route)
            }
        }
    }

    private func computeDrivingTimeSeconds(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> (TimeInterval, CLLocationDistance) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, err in
                if let err = err { continuation.resume(throwing: err); return }
                guard let route = response?.routes.first else {
                    continuation.resume(throwing: TripServiceError.serverError)
                    return
                }
                continuation.resume(returning: (route.expectedTravelTime, route.distance))
            }
        }
    }
    
    private func computeTransitTimeSeconds(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> (TimeInterval, CLLocationDistance) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .transit
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            directions.calculate { response, err in
                if let err = err { continuation.resume(throwing: err); return }
                guard let route = response?.routes.first else {
                    continuation.resume(throwing: TripServiceError.serverError)
                    return
                }
                continuation.resume(returning: (route.expectedTravelTime, route.distance))
            }
        }
    }

    func computeMKRoutes(for option: TripResponse.RouteOption) async -> [MKRoute] {
        var routes: [MKRoute] = []
        for seg in option.segments {
            do {
                let r = try await computeMKRouteForSegment(seg)
                routes.append(r)
            } catch {
                continue
            }
        }
        return routes
    }
    
}
    private func computeMKOriginalRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        preferredTransport: PreferredTransportType
    ) async throws -> TripResponse.RouteOption {
        func calcRoute(transport: MKDirectionsTransportType) async throws -> MKRoute {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = transport
            request.requestsAlternateRoutes = false

            let directions = MKDirections(request: request)
            return try await withCheckedThrowingContinuation { continuation in
                directions.calculate { response, err in
                    if let err = err { continuation.resume(throwing: err); return }
                    guard let mkRoute = response?.routes.first else {
                        continuation.resume(throwing: TripServiceError.serverError)
                        return
                    }
                    continuation.resume(returning: mkRoute)
                }
            }
        }

    let useTransit = (preferredTransport == .gtfs)
    let route: MKRoute
    var fellBackToDriving = false
        do {
            route = try await calcRoute(transport: useTransit ? .transit : .automobile)
        } catch {
            if useTransit, let mkErr = error as NSError?, mkErr.domain == MKErrorDomain, mkErr.code == MKError.directionsNotFound.rawValue {
                fellBackToDriving = true
                route = try await calcRoute(transport: .automobile)
            } else {
                throw error
            }
        }

    // Debug: print Apple MapKit route sections for the original route
    #if DEBUG
    print("\n=== MKRoute Debug: Original (\(useTransit ? "transit" : "driving")) ===")
    let totalDist = String(format: "%.1f km", route.distance / 1000.0)
    let totalDur = String(format: "%.0f s", route.expectedTravelTime)
    print("Route name: \(route.name)")
    print("Total distance: \(totalDist), Total duration: \(totalDur), stepCount=\(route.steps.count)")
    if !route.advisoryNotices.isEmpty {
        print("Notices: \(route.advisoryNotices.joined(separator: " | "))")
    }
    for (idx, step) in route.steps.enumerated() {
        let dist = String(format: "%.0f m", step.distance)
        let instr = step.instructions.isEmpty ? "(no instruction)" : step.instructions
        print(String(format: "  [%02d] %@ — %@", idx, dist, instr))
    }
    print("=== End MKRoute Debug ===\n")
    #endif

    let distanceM = route.distance
    let durationS = route.expectedTravelTime
    let km = distanceM / 1000.0

    var transport: HealthTransportType = (preferredTransport == .car) ? .driving : .transit
        let calories: Int
        let co2: Double
    if transport == .driving {
            calories = 0
            co2 = km * 0.21
        } else {
            calories = Int(km * 5) // small walking to/from stops
            co2 = km * 0.05
        }

        let startLP = TripRequest.LocationPoint(latitude: origin.latitude, longitude: origin.longitude, address: nil)
        let endLP = TripRequest.LocationPoint(latitude: destination.latitude, longitude: destination.longitude, address: nil)
    // Keep transport as selected by user; if transit is chosen but MKDirections fell back to driving,
    // still present this as a transit usual route for consistency with the user's choice.

        let segment = TripResponse.RouteOption.RouteSegment(
            transportType: transport,
            duration: durationS,
            distance: distanceM,
            instructions: (transport == .driving ? "Drive to destination" : "Take transit to destination"),
            startLocation: startLP,
            endLocation: endLP,
            polyline: nil
        )
        return TripResponse.RouteOption(
            id: "mk_original",
            segments: [segment],
            totalDuration: durationS,
            totalDistance: distanceM,
            estimatedCalories: calories,
            healthScore: (transport == .driving) ? 1 : 3,
            carbonFootprint: co2
        )
    }


enum TripServiceError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error occurred"
        case .decodingError:
            return "Failed to parse server response"
        }
    }
}
