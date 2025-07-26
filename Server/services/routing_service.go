package services

import (
	"context"
	"fmt"
	"github.com/mohamedthameursassi/GoServer/models"
	"sort"
	"time"
)

type RoutingService struct {
	bixiService    *BixiService
	carService     *CarService
	walkingService *WalkingService
	//	bikingService  *BikingService
	//	transitService *PublicTransitService
	// les deux autres modes de transports seront ajouté au cours de la semaine
	// pour le moment on fait marche bixi et voiture

}

func NewRoutingService() *RoutingService {
	return &RoutingService{
		bixiService:    NewBixiService(),
		carService:     NewCarService(),
		walkingService: NewWalkingService(),
		//		bikingService:  NewBikingService(),
		//		transitService: NewPublicTransitService(),
	}
}

func (rs *RoutingService) CalculateRoutes(ctx context.Context, req models.RouteRequest) ([]models.Route, error) {
	var routes []models.Route

	// Calculate single-mode routes
	for _, mode := range req.Modes {
		route, err := rs.calculateSingleModeRoute(ctx, mode, req)
		if err != nil {
			continue // Skip if mode not available
		}
		routes = append(routes, route)
	}

	// Calculate multi-modal combinations if multiple modes requested
	if len(req.Modes) > 1 {
		multiRoutes := rs.calculateMultiModalRoutes(ctx, req)
		routes = append(routes, multiRoutes...)
	}

	return rs.optimizeRoutes(routes, req.Preferences), nil
}

func (rs *RoutingService) calculateSingleModeRoute(ctx context.Context, mode models.TransportMode, req models.RouteRequest) (models.Route, error) {
	switch mode {
	case models.Bixi:
		return rs.bixiService.CalculateRoute(ctx, req.Origin, req.Destination)
	case models.Car:
		return rs.carService.CalculateRoute(ctx, req.Origin, req.Destination)
	case models.Walking:
		return rs.walkingService.CalculateRoute(ctx, req.Origin, req.Destination, nil)
		//	case models.Biking:
		//		return rs.bikingService.CalculateRoute(ctx, req.Origin, req.Destination)
		//	case models.PublicTransit:
		//		return rs.transitService.CalculateRoute(ctx, req.Origin, req.Destination)
	default:
		return models.Route{}, fmt.Errorf("unsupported transport mode: %s", mode)
	}
}

func (rs *RoutingService) calculateMultiModalRoutes(ctx context.Context, req models.RouteRequest) []models.Route {
	var multiRoutes []models.Route

	hasWalking := rs.hasModeInRequest(req.Modes, models.Walking)
	hasCar := rs.hasModeInRequest(req.Modes, models.Car)

	if hasWalking && hasCar {
		walkingCarRoutes, err := rs.calculateWalkingCarRoute(ctx, req)
		if err == nil {
			multiRoutes = append(multiRoutes, walkingCarRoutes...)
		}
	}

	return multiRoutes
}

func (rs *RoutingService) hasModeInRequest(modes []models.TransportMode, targetMode models.TransportMode) bool {
	for _, mode := range modes {
		if mode == targetMode {
			return true
		}
	}
	return false
}

func (rs *RoutingService) optimizeMultiModalRoutes(routes []models.Route) []models.Route {
	// Sort by total time, keep top 3 options
	sort.Slice(routes, func(i, j int) bool {
		return routes[i].TotalTime < routes[j].TotalTime
	})

	if len(routes) > 3 {
		return routes[:3]
	}
	return routes
}
func (rs *RoutingService) optimizeRoutes(routes []models.Route, prefs models.RoutePreferences) []models.Route {
	return routes
}

func (rs *RoutingService) calculateWalkingCarRoute(ctx context.Context, req models.RouteRequest) ([]models.Route, error) {
	var combinedRoutes []models.Route

	// Use default max walking time if not specified
	maxWalkingTime := req.Preferences.MaxWalkTime
	if maxWalkingTime == 0 {
		maxWalkingTime = 10 // 10 minutes default
	}

	// Find all parking locations within walking distance of DESTINATION
	allParkingLocations := rs.walkingService.FindAccessibleParkingLocations(req.Destination, maxWalkingTime*60)

	// Select only the 5 parking locations closest to the car's ORIGIN
	accessibleParkingLocations := rs.walkingService.SelectClosestParkingLocations(req.Origin, allParkingLocations)

	for _, parkingLocation := range accessibleParkingLocations {
		// Calculate CAR route from origin to parking location
		carRoute, err := rs.carService.CalculateRoute(ctx, req.Origin, parkingLocation)
		if err != nil {
			continue
		}

		// Calculate WALKING route from parking location to destination
		walkingRoute, err := rs.walkingService.CalculateRoute(ctx, parkingLocation, req.Destination, nil)
		if err != nil {
			continue
		}

		walkingTimeMinutes := int(walkingRoute.TotalTime.Minutes())
		if walkingTimeMinutes > maxWalkingTime {
			continue
		}

		combinedRoute := models.Route{
			ID:          fmt.Sprintf("car-walking-route-%d", len(combinedRoutes)+1),
			Origin:      req.Origin,
			Destination: req.Destination,
			TotalTime:   carRoute.TotalTime + walkingRoute.TotalTime + (5 * time.Minute), // +5min parking time
			Distance:    carRoute.Distance + walkingRoute.Distance,
			Modes:       []models.TransportMode{models.Car, models.Walking},
			Segments: []models.RouteSegment{
				{
					Mode:         models.Car,
					Origin:       req.Origin,
					Destination:  parkingLocation,
					Duration:     carRoute.TotalTime,
					Distance:     carRoute.Distance,
					Instructions: stringPtr(fmt.Sprintf("Drive to parking location at %s", parkingLocation.Address)),
				},
				{
					Mode:         models.Walking,
					Origin:       parkingLocation,
					Destination:  req.Destination,
					Duration:     walkingRoute.TotalTime,
					Distance:     walkingRoute.Distance,
					Instructions: stringPtr(fmt.Sprintf("Walk from parking to destination (%d minutes)", walkingTimeMinutes)),
				},
			},
		}

		combinedRoutes = append(combinedRoutes, combinedRoute)
	}

	// Apply smart route selection based on shortest car commute + closest to desired walking time
	optimizedRoutes := rs.selectOptimalCarWalkingRoutes(combinedRoutes, req.Preferences)

	return optimizedRoutes, nil
}

// selectOptimalCarWalkingRoutes selects the best routes based on shortest car commute and closest to desired walking time
func (rs *RoutingService) selectOptimalCarWalkingRoutes(routes []models.Route, prefs models.RoutePreferences) []models.Route {
	if len(routes) == 0 {
		return routes
	}

	// Calculate preferred walking time (use MaxWalkTime or default to 10 minutes)
	preferredWalkingTime := prefs.PreferredWalkTime
	if preferredWalkingTime == 0 {
		preferredWalkingTime = prefs.MaxWalkTime
		if preferredWalkingTime == 0 {
			preferredWalkingTime = 10 // Default to 10 minutes
		}
	}

	// Score each route based on our criteria
	type RouteScore struct {
		Route           models.Route
		CarTime         time.Duration
		WalkingTime     time.Duration
		WalkingTimeDiff int     // Difference from preferred walking time in minutes
		CompositeScore  float64 // Lower is better
	}

	var routeScores []RouteScore

	for _, route := range routes {
		// Extract car and walking segments
		var carTime, walkingTime time.Duration
		for _, segment := range route.Segments {
			if segment.Mode == models.Car {
				carTime = segment.Duration
			} else if segment.Mode == models.Walking {
				walkingTime = segment.Duration
			}
		}

		walkingMinutes := int(walkingTime.Minutes())
		walkingTimeDiff := abs(walkingMinutes - preferredWalkingTime)

		// Composite score calculation:
		// - Car time weight: 60% (prioritize shorter driving)
		// - Walking time difference weight: 40% (prefer closer to desired walking time)
		carTimeScore := float64(carTime.Minutes()) * 0.6
		walkingDiffScore := float64(walkingTimeDiff) * 0.4
		compositeScore := carTimeScore + walkingDiffScore

		routeScores = append(routeScores, RouteScore{
			Route:           route,
			CarTime:         carTime,
			WalkingTime:     walkingTime,
			WalkingTimeDiff: walkingTimeDiff,
			CompositeScore:  compositeScore,
		})
	}

	// Sort by composite score (lowest is best)
	sort.Slice(routeScores, func(i, j int) bool {
		return routeScores[i].CompositeScore < routeScores[j].CompositeScore
	})

	// Return top 3 routes with enhanced descriptions
	maxRoutes := 3
	if len(routeScores) < maxRoutes {
		maxRoutes = len(routeScores)
	}

	var optimizedRoutes []models.Route
	for i := 0; i < maxRoutes; i++ {
		score := routeScores[i]
		route := score.Route

		// Update route ID with optimization info
		route.ID = fmt.Sprintf("optimal-car-walk-%d (drive: %dm, walk: %dm)",
			i+1, int(score.CarTime.Minutes()), int(score.WalkingTime.Minutes()))

		// Add optimization details to car segment instructions
		for j := range route.Segments {
			if route.Segments[j].Mode == models.Car {
				route.Segments[j].Instructions = stringPtr(fmt.Sprintf("%s (optimal: %dm drive, %dm walk)",
					*route.Segments[j].Instructions,
					int(score.CarTime.Minutes()),
					int(score.WalkingTime.Minutes())))
			}
		}

		optimizedRoutes = append(optimizedRoutes, route)
	}

	return optimizedRoutes
}

// Helper function to calculate absolute value
func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func (ws *WalkingService) FindAccessibleCarLocations(origin models.Location, maxWalkingTimeSeconds int) []models.Location {
	return ws.FindAccessibleParkingLocations(origin, maxWalkingTimeSeconds)
}
