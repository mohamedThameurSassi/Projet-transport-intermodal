package services

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/mohamedthameursassi/GoServer/models"
	"math"
	"net/http"
	"sort"
	"time"
)

type WalkingOptions struct {
	WalkingSpeed float64
	EndPosition  *models.Location
}

type OSRMResponse struct {
	Code   string      `json:"code"`
	Routes []OSRMRoute `json:"routes"`
}

type OSRMRoute struct {
	Distance float64 `json:"distance"`
	Duration float64 `json:"duration"`
	Geometry string  `json:"geometry"`
}

type WalkingService struct {
	osrmBaseURL string
	httpClient  *http.Client
}

func NewWalkingService() *WalkingService {
	return &WalkingService{
		osrmBaseURL: "http://router.project-osrm.org/route/v1/foot",
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (ws *WalkingService) CalculateRoute(ctx context.Context, origin, destination models.Location, opts *WalkingOptions) (models.Route, error) {
	if opts == nil {
		opts = &WalkingOptions{
			WalkingSpeed: 4.8,
		}
	}

	if opts.WalkingSpeed <= 0 {
		opts.WalkingSpeed = 4.8
	}

	actualDestination := destination
	if opts.EndPosition != nil {
		actualDestination = *opts.EndPosition
	}

	walkingSpeedMPS := opts.WalkingSpeed * 1000 / 3600

	originCoord := fmt.Sprintf("%f,%f", origin.Latitude, origin.Longitude)
	destinationCoord := fmt.Sprintf("%f,%f", actualDestination.Latitude, actualDestination.Longitude)

	url := fmt.Sprintf("%s/%s;%s?overview=false", ws.osrmBaseURL, originCoord, destinationCoord)

	resp, err := ws.httpClient.Get(url)
	if err != nil {
		return models.Route{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return models.Route{}, fmt.Errorf("OSRM request failed with status: %s", resp.Status)
	}

	var osrmResponse OSRMResponse
	if err := json.NewDecoder(resp.Body).Decode(&osrmResponse); err != nil {
		return models.Route{}, err
	}

	if osrmResponse.Code != "Ok" {
		return models.Route{}, fmt.Errorf("OSRM response error: %s", osrmResponse.Code)
	}

	route := osrmResponse.Routes[0]

	expectedDuration := route.Distance / walkingSpeedMPS

	adjustedDuration := math.Max(expectedDuration, route.Duration)

	return models.Route{
		Distance: route.Distance,
		Duration: time.Duration(adjustedDuration),
	}, nil
}

func (ws *WalkingService) FinishRoute(destination, start, latestStartLocation models.Location, walktime time.Duration) (models.Route, error) {
	radius := float64(walktime.Seconds()) * 4.8 / 3600 * 1000

	var candidatePoints []models.Location

	radiusPercentages := []float64{0.9, 1.0}
	numPointsPerCircle := 20

	for _, radiusPercent := range radiusPercentages {
		currentRadius := radius * radiusPercent

		for i := 0; i < numPointsPerCircle; i++ {
			angle := float64(i) * 2 * math.Pi / float64(numPointsPerCircle)

			radiusInDegrees := currentRadius / 111000.0

			lat := destination.Latitude + radiusInDegrees*math.Cos(angle)
			lng := destination.Longitude + radiusInDegrees*math.Sin(angle)/math.Cos(destination.Latitude*math.Pi/180)

			candidatePoints = append(candidatePoints, models.Location{
				Latitude:  lat,
				Longitude: lng,
			})
		}
	}

	var validRoutes []models.Route
	targetDuration := walktime
	tolerance := 0.2

	for _, point := range candidatePoints {
		route, err := ws.calculateOSRMRoute(latestStartLocation, point)
		if err == nil {
			minDuration := float64(targetDuration) * (1 - tolerance)
			maxDuration := float64(targetDuration) * (1 + tolerance)
			routeDuration := float64(route.Duration)

			if routeDuration >= minDuration && routeDuration <= maxDuration {
				validRoutes = append(validRoutes, route)
			}
		}
	}

	if len(validRoutes) == 0 {
		return models.Route{}, fmt.Errorf("no valid routes found within ±20%% of target walk time")
	}

	sort.Slice(validRoutes, func(i, j int) bool {
		diffI := math.Abs(float64(validRoutes[i].Duration) - float64(targetDuration))
		diffJ := math.Abs(float64(validRoutes[j].Duration) - float64(targetDuration))
		return diffI < diffJ
	})

	return validRoutes[0], nil
}

func (ws *WalkingService) calculateOSRMRoute(origin, destination models.Location) (models.Route, error) {
	originCoord := fmt.Sprintf("%f,%f", origin.Longitude, origin.Latitude)
	destinationCoord := fmt.Sprintf("%f,%f", destination.Longitude, destination.Latitude)

	url := fmt.Sprintf("%s/%s;%s?overview=false", ws.osrmBaseURL, originCoord, destinationCoord)

	resp, err := ws.httpClient.Get(url)
	if err != nil {
		return models.Route{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return models.Route{}, fmt.Errorf("OSRM request failed with status: %s", resp.Status)
	}

	var osrmResponse OSRMResponse
	if err := json.NewDecoder(resp.Body).Decode(&osrmResponse); err != nil {
		return models.Route{}, err
	}

	if osrmResponse.Code != "Ok" || len(osrmResponse.Routes) == 0 {
		return models.Route{}, fmt.Errorf("no route found")
	}

	route := osrmResponse.Routes[0]

	return models.Route{
		Distance: route.Distance,
		Duration: time.Duration(route.Duration * float64(time.Second)),
	}, nil
}

func (ws *WalkingService) FindAccessibleParkingLocations(destination models.Location, maxWalkingTimeSeconds int) []models.Location {
	// Generate parking locations around the destination within walking distance
	var parkingLocations []models.Location

	walkingSpeed := 4.8                                                        // km/h
	maxDistance := float64(maxWalkingTimeSeconds) * walkingSpeed / 3600 * 1000 // meters

	// Generate grid of parking locations around destination
	numPoints := 12
	for i := 0; i < numPoints; i++ {
		angle := float64(i) * 2 * math.Pi / float64(numPoints)

		// Create parking spots at various distances within the max range
		distances := []float64{0.3, 0.5, 0.7, 0.9} // 30%, 50%, 70%, 90% of max distance

		for _, distPercent := range distances {
			currentDistance := maxDistance * distPercent
			radiusInDegrees := currentDistance / 111000.0

			lat := destination.Latitude + radiusInDegrees*math.Cos(angle)
			lng := destination.Longitude + radiusInDegrees*math.Sin(angle)/math.Cos(destination.Latitude*math.Pi/180)

			parkingLocations = append(parkingLocations, models.Location{
				Latitude:  lat,
				Longitude: lng,
				Address:   fmt.Sprintf("Parking spot %.0fm from destination", currentDistance),
			})
		}
	}

	return parkingLocations
}

func (ws *WalkingService) SelectClosestParkingLocations(origin models.Location, allParkingLocations []models.Location) []models.Location {
	if len(allParkingLocations) <= 5 {
		return allParkingLocations
	}

	// Calculate distance from origin to each parking location
	type LocationDistance struct {
		Location models.Location
		Distance float64
	}

	var locationDistances []LocationDistance

	for _, parking := range allParkingLocations {
		distance := ws.calculateHaversineDistance(origin, parking)
		locationDistances = append(locationDistances, LocationDistance{
			Location: parking,
			Distance: distance,
		})
	}

	// Sort by distance and return top 5
	sort.Slice(locationDistances, func(i, j int) bool {
		return locationDistances[i].Distance < locationDistances[j].Distance
	})

	var closestLocations []models.Location
	maxLocations := 5
	if len(locationDistances) < maxLocations {
		maxLocations = len(locationDistances)
	}

	for i := 0; i < maxLocations; i++ {
		closestLocations = append(closestLocations, locationDistances[i].Location)
	}

	return closestLocations
}

func (ws *WalkingService) calculateHaversineDistance(origin, destination models.Location) float64 {
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
