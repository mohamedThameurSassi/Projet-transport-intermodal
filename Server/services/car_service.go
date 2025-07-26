package services

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/mohamedthameursassi/GoServer/models"
	"math"
	"net/http"
	"time"
)

// OSRM API response structures for car routing
type OSRMCarResponse struct {
	Code   string         `json:"code"`
	Routes []OSRMCarRoute `json:"routes"`
}

type OSRMCarRoute struct {
	Distance float64 `json:"distance"` // in meters
	Duration float64 `json:"duration"` // in seconds
	Geometry string  `json:"geometry"`
}

type CarService struct {
	osrmBaseURL string
	httpClient  *http.Client
}

func NewCarService() *CarService {
	return &CarService{
		osrmBaseURL: "http://router.project-osrm.org/route/v1/driving", // OSRM demo server for car routing
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (cs *CarService) CalculateRoute(ctx context.Context, origin, destination models.Location) (models.Route, error) {
	// Try OSRM first for realistic car routing
	route, err := cs.CalculateRouteWithOSRM(ctx, origin, destination)
	if err == nil {
		return route, nil
	}

	// Fallback to basic calculation if OSRM fails
	// Estimate driving time based on straight-line distance and average speed
	distance := cs.calculateHaversineDistance(origin, destination)
	avgSpeed := 50.0 // km/h average driving speed in city
	drivingTimeHours := distance / avgSpeed
	drivingTime := time.Duration(drivingTimeHours*3600) * time.Second

	segment := models.RouteSegment{
		Mode:         models.Car,
		Origin:       origin,
		Destination:  destination,
		Duration:     drivingTime,
		Distance:     distance * 1000, // convert km to meters
		Instructions: stringPtr(fmt.Sprintf("Drive to destination (estimated: %.1f km)", distance)),
	}

	return models.Route{
		ID:          "car-route-fallback",
		Origin:      origin,
		Destination: destination,
		Segments:    []models.RouteSegment{segment},
		TotalTime:   drivingTime,
		Distance:    distance * 1000,
		Modes:       []models.TransportMode{models.Car},
	}, nil
}

// getCarRouteFromOSRM calls the OSRM API to get realistic car route
func (cs *CarService) getCarRouteFromOSRM(ctx context.Context, origin, destination models.Location) (*OSRMCarRoute, error) {
	// Build OSRM API URL: lng,lat;lng,lat format
	url := fmt.Sprintf("%s/%.6f,%.6f;%.6f,%.6f?overview=false&alternatives=false&steps=false",
		cs.osrmBaseURL,
		origin.Longitude, origin.Latitude,
		destination.Longitude, destination.Latitude,
	)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := cs.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to call OSRM API: %w", err)
	}
	defer func() {
		if closeErr := resp.Body.Close(); closeErr != nil {
			// Log error but don't fail the request
		}
	}()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OSRM API returned status %d", resp.StatusCode)
	}

	var osrmResp OSRMCarResponse
	if err := json.NewDecoder(resp.Body).Decode(&osrmResp); err != nil {
		return nil, fmt.Errorf("failed to decode OSRM response: %w", err)
	}

	if osrmResp.Code != "Ok" || len(osrmResp.Routes) == 0 {
		return nil, fmt.Errorf("no car route found")
	}

	return &osrmResp.Routes[0], nil
}

// CalculateRouteWithOSRM calculates car route using OpenStreetMap data
func (cs *CarService) CalculateRouteWithOSRM(ctx context.Context, origin, destination models.Location) (models.Route, error) {
	osrmRoute, err := cs.getCarRouteFromOSRM(ctx, origin, destination)
	if err != nil {
		return models.Route{}, err
	}

	drivingTime := time.Duration(osrmRoute.Duration) * time.Second

	segment := models.RouteSegment{
		Mode:        models.Car,
		Origin:      origin,
		Destination: destination,
		Duration:    drivingTime,
		Distance:    osrmRoute.Distance,
		Instructions: stringPtr(fmt.Sprintf("Drive to destination (%.1f km, %d minutes)",
			osrmRoute.Distance/1000, int(drivingTime.Minutes()))),
		Polyline: stringPtr(osrmRoute.Geometry),
	}

	return models.Route{
		ID:          "car-route-osrm",
		Origin:      origin,
		Destination: destination,
		Segments:    []models.RouteSegment{segment},
		TotalTime:   drivingTime,
		Distance:    osrmRoute.Distance,
		Modes:       []models.TransportMode{models.Car},
	}, nil
}

// calculateHaversineDistance calculates the distance between two locations using the Haversine formula
func (cs *CarService) calculateHaversineDistance(origin, destination models.Location) float64 {
	const earthRadius = 6371 // Earth's radius in kilometers

	lat1Rad := origin.Latitude * math.Pi / 180
	lat2Rad := destination.Latitude * math.Pi / 180
	deltaLatRad := (destination.Latitude - origin.Latitude) * math.Pi / 180
	deltaLngRad := (destination.Longitude - origin.Longitude) * math.Pi / 180

	a := math.Sin(deltaLatRad/2)*math.Sin(deltaLatRad/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(deltaLngRad/2)*math.Sin(deltaLngRad/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadius * c
}

func stringPtr(s string) *string {
	return &s
}
