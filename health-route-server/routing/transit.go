package routing

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"health-route-server/preprocessing"
)

type GoogleMapsConfig struct {
	APIKey string
}

func LoadGoogleMapsConfig() (*GoogleMapsConfig, error) {
	apiKey := os.Getenv("GOOGLE_MAPS_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GOOGLE_MAPS_API_KEY environment variable not set")
	}

	return &GoogleMapsConfig{
		APIKey: apiKey,
	}, nil
}

// Google Maps API response structures
type GoogleDirectionsResponse struct {
	Routes       []GoogleRoute `json:"routes"`
	Status       string        `json:"status"`
	ErrorMessage string        `json:"error_message,omitempty"`
}

type GoogleRoute struct {
	Legs     []GoogleLeg    `json:"legs"`
	Overview GooglePolyline `json:"overview_polyline"`
}

type GoogleLeg struct {
	Steps         []GoogleStep   `json:"steps"`
	Duration      GoogleDuration `json:"duration"`
	Distance      GoogleDistance `json:"distance"`
	StartLocation GoogleLocation `json:"start_location"`
	EndLocation   GoogleLocation `json:"end_location"`
}

type GoogleStep struct {
	TravelMode     string          `json:"travel_mode"`
	Duration       GoogleDuration  `json:"duration"`
	Distance       GoogleDistance  `json:"distance"`
	StartLocation  GoogleLocation  `json:"start_location"`
	EndLocation    GoogleLocation  `json:"end_location"`
	Instructions   string          `json:"html_instructions"`
	Polyline       GooglePolyline  `json:"polyline"`
	TransitDetails *TransitDetails `json:"transit_details,omitempty"`
	Steps          []GoogleStep    `json:"steps,omitempty"`
}

type TransitDetails struct {
	DepartureStop TransitStop `json:"departure_stop"`
	ArrivalStop   TransitStop `json:"arrival_stop"`
	DepartureTime TransitTime `json:"departure_time"`
	ArrivalTime   TransitTime `json:"arrival_time"`
	Line          TransitLine `json:"line"`
	NumStops      int         `json:"num_stops"`
}

type TransitStop struct {
	Name     string         `json:"name"`
	Location GoogleLocation `json:"location"`
}

type TransitTime struct {
	Value    int64  `json:"value"`
	Text     string `json:"text"`
	TimeZone string `json:"time_zone"`
}

type TransitLine struct {
	Name      string          `json:"name"`
	ShortName string          `json:"short_name"`
	Color     string          `json:"color"`
	Vehicle   TransitVehicle  `json:"vehicle"`
	Agencies  []TransitAgency `json:"agencies"`
}

type TransitVehicle struct {
	Name string `json:"name"`
	Type string `json:"type"`
	Icon string `json:"icon"`
}

type TransitAgency struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

type GoogleDuration struct {
	Value int    `json:"value"`
	Text  string `json:"text"`
}

type GoogleDistance struct {
	Value int    `json:"value"`
	Text  string `json:"text"`
}

type GoogleLocation struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type GooglePolyline struct {
	Points string `json:"points"`
}

// Main function to get transit directions from Google Maps
func PlanTransitWithGoogle(
	startCoord Coordinate,
	endCoord Coordinate,
	config *GoogleMapsConfig,
	departureTime *time.Time,
	maxWalkMinutes float64,
) ([]RouteStep, error) {
	log.Printf("=== Starting Google Maps Transit Routing ===")
	log.Printf("Start: (%.6f, %.6f), End: (%.6f, %.6f)",
		startCoord.Lat, startCoord.Lon, endCoord.Lat, endCoord.Lon)

	baseURL := "https://maps.googleapis.com/maps/api/directions/json"
	params := url.Values{}

	params.Set("origin", fmt.Sprintf("%.6f,%.6f", startCoord.Lat, startCoord.Lon))
	params.Set("destination", fmt.Sprintf("%.6f,%.6f", endCoord.Lat, endCoord.Lon))
	params.Set("mode", "transit")
	params.Set("key", config.APIKey)

	// Request alternatives
	params.Set("alternatives", "true")
	params.Set("units", "metric")

	if departureTime != nil {
		params.Set("departure_time", fmt.Sprintf("%d", departureTime.Unix()))
	} else {
		params.Set("departure_time", "now")
	}

	// Optimize for less walking if specified
	if maxWalkMinutes > 0 && maxWalkMinutes < 30 {
		params.Set("transit_routing_preference", "less_walking")
	}

	requestURL := fmt.Sprintf("%s?%s", baseURL, params.Encode())
	log.Printf("Making Google Maps API request...")

	resp, err := http.Get(requestURL)
	if err != nil {
		return nil, fmt.Errorf("failed to call Google Maps API: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}

	var googleResp GoogleDirectionsResponse
	if err := json.Unmarshal(body, &googleResp); err != nil {
		return nil, fmt.Errorf("failed to parse Google Maps response: %v", err)
	}

	if googleResp.Status != "OK" {
		log.Printf("Google Maps API error: %s - %s", googleResp.Status, googleResp.ErrorMessage)
		return nil, fmt.Errorf("google Maps API error: %s", googleResp.Status)
	}

	if len(googleResp.Routes) == 0 {
		return nil, fmt.Errorf("no transit routes found")
	}

	// Use the best route (first one)
	bestRoute := googleResp.Routes[0]
	steps := convertGoogleRouteToSteps(bestRoute, startCoord, endCoord)

	log.Printf("=== Google Maps Transit Routing completed with %d steps ===", len(steps))
	return steps, nil
}

func convertGoogleRouteToSteps(route GoogleRoute, startCoord, endCoord Coordinate) []RouteStep {
	steps := make([]RouteStep, 0)

	for _, leg := range route.Legs {
		for _, googleStep := range leg.Steps {
			step := convertGoogleStep(googleStep)
			if step != nil {
				steps = append(steps, *step)
			}
		}
	}

	// Ensure start and end coordinates match exactly
	if len(steps) > 0 {
		steps[0].FromCoord = startCoord
		steps[len(steps)-1].ToCoord = endCoord
	}

	return steps
}

func convertGoogleStep(googleStep GoogleStep) *RouteStep {
	step := &RouteStep{
		FromCoord: Coordinate{
			Lat: googleStep.StartLocation.Lat,
			Lon: googleStep.StartLocation.Lng,
		},
		ToCoord: Coordinate{
			Lat: googleStep.EndLocation.Lat,
			Lon: googleStep.EndLocation.Lng,
		},
		DurationSec: float64(googleStep.Duration.Value),
		DistanceM:   float64(googleStep.Distance.Value),
	}

	switch googleStep.TravelMode {
	case "WALKING":
		step.Mode = "walk"
		instructions := stripHTMLTags(googleStep.Instructions)
		step.Description = fmt.Sprintf("Walk %.1f km (%.0f min) - %s",
			step.DistanceM/1000, step.DurationSec/60, instructions)

	case "TRANSIT":
		if googleStep.TransitDetails != nil {
			td := googleStep.TransitDetails
			step.Mode = "transit"

			vehicleType := "Transit"
			if td.Line.Vehicle.Name != "" {
				vehicleType = td.Line.Vehicle.Name
			}

			lineName := td.Line.Name
			if td.Line.ShortName != "" {
				lineName = fmt.Sprintf("%s (%s)", td.Line.ShortName, td.Line.Name)
			}

			step.Description = fmt.Sprintf("%s: %s from %s to %s (%d stops, %.0f min)",
				vehicleType,
				lineName,
				td.DepartureStop.Name,
				td.ArrivalStop.Name,
				td.NumStops,
				step.DurationSec/60,
			)

			// Set precise stop locations
			step.FromCoord = Coordinate{
				Lat: td.DepartureStop.Location.Lat,
				Lon: td.DepartureStop.Location.Lng,
			}
			step.ToCoord = Coordinate{
				Lat: td.ArrivalStop.Location.Lat,
				Lon: td.ArrivalStop.Location.Lng,
			}
		} else {
			step.Mode = "transit"
			step.Description = fmt.Sprintf("Transit (%.1f km, %.0f min)",
				step.DistanceM/1000, step.DurationSec/60)
		}

	case "DRIVING":
		step.Mode = "car"
		step.Description = fmt.Sprintf("Drive %.1f km (%.0f min)",
			step.DistanceM/1000, step.DurationSec/60)

	default:
		step.Mode = strings.ToLower(googleStep.TravelMode)
		step.Description = fmt.Sprintf("%s (%.1f km, %.0f min)",
			googleStep.TravelMode, step.DistanceM/1000, step.DurationSec/60)
	}

	return step
}

func stripHTMLTags(html string) string {
	// Simple HTML tag removal
	result := html
	result = strings.ReplaceAll(result, "<b>", "")
	result = strings.ReplaceAll(result, "</b>", "")
	result = strings.ReplaceAll(result, "<div>", "")
	result = strings.ReplaceAll(result, "</div>", "")
	result = strings.ReplaceAll(result, "&nbsp;", " ")
	return result
}

// Wrapper function for easier use
func PlanTransitPlusWalk(
	startCoord Coordinate,
	endCoord Coordinate,
	maxWalkMinutes float64,
) ([]RouteStep, error) {
	config, err := LoadGoogleMapsConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load Google Maps config: %v", err)
	}

	steps, err := PlanTransitWithGoogle(
		startCoord,
		endCoord,
		config,
		nil, // Use current time
		maxWalkMinutes,
	)

	if err != nil {
		return nil, err
	}

	// Tag walking steps appropriately
	for i := range steps {
		if steps[i].Mode == "walk" {
			// Determine if this is walking to transit, from transit, or between transit
			if i == 0 || (i > 0 && steps[i-1].Mode != "walk") {
				if i < len(steps)-1 && steps[i+1].Mode == "transit" {
					steps[i].Mode = "walk_to_transit"
				}
			} else if i == len(steps)-1 || (i < len(steps)-1 && steps[i+1].Mode != "walk") {
				if i > 0 && steps[i-1].Mode == "transit" {
					steps[i].Mode = "walk_from_transit"
				}
			}
		}
	}

	// Validate total walking time
	totalWalkSec := 0.0
	for _, step := range steps {
		if step.Mode == "walk" || step.Mode == "walk_to_transit" || step.Mode == "walk_from_transit" {
			totalWalkSec += step.DurationSec
		}
	}

	log.Printf("Route includes %.1f minutes of walking (max allowed: %.1f)",
		totalWalkSec/60, maxWalkMinutes)

	return steps, nil
}

// Function to get multiple transit alternatives
func GetTransitAlternatives(
	startCoord Coordinate,
	endCoord Coordinate,
	config *GoogleMapsConfig,
	departureTime *time.Time,
) ([][]RouteStep, error) {
	log.Printf("Getting transit alternatives from Google Maps")

	baseURL := "https://maps.googleapis.com/maps/api/directions/json"
	params := url.Values{}

	params.Set("origin", fmt.Sprintf("%.6f,%.6f", startCoord.Lat, startCoord.Lon))
	params.Set("destination", fmt.Sprintf("%.6f,%.6f", endCoord.Lat, endCoord.Lon))
	params.Set("mode", "transit")
	params.Set("key", config.APIKey)
	params.Set("alternatives", "true")
	params.Set("units", "metric")

	if departureTime != nil {
		params.Set("departure_time", fmt.Sprintf("%d", departureTime.Unix()))
	} else {
		params.Set("departure_time", "now")
	}

	requestURL := fmt.Sprintf("%s?%s", baseURL, params.Encode())

	resp, err := http.Get(requestURL)
	if err != nil {
		return nil, fmt.Errorf("failed to call Google Maps API: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}

	var googleResp GoogleDirectionsResponse
	if err := json.Unmarshal(body, &googleResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %v", err)
	}

	if googleResp.Status != "OK" {
		return nil, fmt.Errorf("google Maps API error: %s", googleResp.Status)
	}

	alternatives := make([][]RouteStep, 0, len(googleResp.Routes))
	for _, route := range googleResp.Routes {
		steps := convertGoogleRouteToSteps(route, startCoord, endCoord)
		alternatives = append(alternatives, steps)
	}

	log.Printf("Found %d alternative transit routes", len(alternatives))
	return alternatives, nil
}

// PlanTransitEarlierStopPlusWalk attempts to alight earlier from the final transit segment to maximize healthy walking under a time cap.
// Workflow:
// 1) Get a baseline transit itinerary from Google (PlanTransitWithGoogle)
// 2) Take the last transit step's arrival stop coords
// 3) Match to nearest GTFS stop (preloaded index)
// 4) In the same canonical trip pattern, enumerate earlier stops
// 5) For each earlier stop, compute walking time (A*) to destination
// 6) Pick the earliest (farthest upstream) stop whose walk time is the largest <= maxWalkMinutes; fallback to shortest walk if none fit
func PlanTransitEarlierStopPlusWalk(
	startCoord Coordinate,
	endCoord Coordinate,
	maxWalkMinutes float64,
	walkGraph *Graph,
) ([]RouteStep, error) {
	log.Printf("=== PlanTransitEarlierStopPlusWalk ===")
	log.Printf("Start(%.6f,%.6f) End(%.6f,%.6f) Walk cap: %.1f min WalkGraph nodes: %d", startCoord.Lat, startCoord.Lon, endCoord.Lat, endCoord.Lon, maxWalkMinutes, len(walkGraph.Nodes))

	cfg, err := LoadGoogleMapsConfig()
	if err != nil {
		return nil, fmt.Errorf("google maps config: %w", err)
	}
	baseSteps, err := PlanTransitWithGoogle(startCoord, endCoord, cfg, ptrNow(), 0)
	if err != nil {
		return nil, fmt.Errorf("google directions: %w", err)
	}

	lastTransitIdx := -1
	for i := len(baseSteps) - 1; i >= 0; i-- {
		if baseSteps[i].Mode == "transit" {
			lastTransitIdx = i
			break
		}
	}
	if lastTransitIdx == -1 {
		return baseSteps, fmt.Errorf("no transit segment found in baseline route")
	}
	lastTransit := baseSteps[lastTransitIdx]

	gtfsIdx := preprocessing.GetGTFSIndex()
	if gtfsIdx == nil {
		return baseSteps, fmt.Errorf("gtfs index not loaded")
	}

	nearestStop, distM := preprocessing.FindClosestGTFSStop(lastTransit.ToCoord.Lat, lastTransit.ToCoord.Lon, gtfsIdx)
	log.Printf("Matched Google arrival to GTFS stop %s (%.0fm)", nearestStop.Name, distM)
	tripID, routeID, dir, err := preprocessing.ChooseCanonicalTripThatContainsStop(nearestStop.ID, gtfsIdx)
	if err != nil {
		return baseSteps, fmt.Errorf("canonical trip: %w", err)
	}
	log.Printf("Canonical trip selected: trip=%s route=%s dir=%d", tripID, routeID, dir)
	beforeStops, seq, err := preprocessing.StopsBeforeInSameTrip(nearestStop.ID, tripID, gtfsIdx)
	if err != nil {
		return baseSteps, fmt.Errorf("earlier stops: %w", err)
	}
	if len(beforeStops) == 0 {
		return baseSteps, fmt.Errorf("no earlier stops before stop %s (seq=%d)", nearestStop.ID, seq)
	}

	maxWalkSec := maxWalkMinutes * 60
	destNode, _ := findNearestNode(endCoord, walkGraph)

	var chosen *preprocessing.GTFSStop
	var chosenWalkTime, chosenWalkDist float64
	var chosenCoord Coordinate

	for _, cand := range beforeStops {
		candCoord := Coordinate{Lat: cand.Lat, Lon: cand.Lon}
		candNode, _ := findNearestNode(candCoord, walkGraph)
		_, walkTime, walkDist := findShortestPathAStar(walkGraph, candNode, destNode, "walk")
		if walkTime <= 0 || math.IsInf(walkTime, 1) {
			continue
		}
		if walkTime <= maxWalkSec && walkTime > chosenWalkTime {
			candCopy := cand
			chosen = &candCopy
			chosenWalkTime = walkTime
			chosenWalkDist = walkDist
			chosenCoord = candCoord
		}
	}

	if chosen == nil {
		var fallback *preprocessing.GTFSStop
		bestDiff := math.Inf(1)
		for _, cand := range beforeStops {
			candCoord := Coordinate{Lat: cand.Lat, Lon: cand.Lon}
			candNode, _ := findNearestNode(candCoord, walkGraph)
			_, walkTime, walkDist := findShortestPathAStar(walkGraph, candNode, destNode, "walk")
			if walkTime <= 0 || math.IsInf(walkTime, 1) {
				continue
			}
			// Since no candidate was <= maxWalkSec, all walkTime > maxWalkSec; choose the one closest to the cap
			diff := math.Abs(walkTime - maxWalkSec*60)
			if diff < bestDiff {
				candCopy := cand
				fallback = &candCopy
				bestDiff = diff
				chosenWalkTime = walkTime
				chosenWalkDist = walkDist
				chosenCoord = candCoord
			}
		}
		if fallback == nil {
			return baseSteps, fmt.Errorf("no workable walking connection from earlier stops")
		}
		log.Printf("Fallback earlier alight stop chosen (closest to target walk time %.1f min): %s (walk %.1f min)", maxWalkSec/60, fallback.Name, chosenWalkTime/60)
		chosen = fallback
	}

	log.Printf("Chosen earlier alight stop: %s (walk %.1f min, %.0fm)", chosen.Name, chosenWalkTime/60, chosenWalkDist)

	out := make([]RouteStep, 0, len(baseSteps)+2)
	if lastTransitIdx > 0 {
		out = append(out, baseSteps[:lastTransitIdx]...)
	}

	transitDist := haversineDistance(lastTransit.FromCoord, chosenCoord)
	transitTime := transitDist / DEFAULT_SUBWAY_SPEED_M_S
	out = append(out, RouteStep{
		Mode:        "transit",
		FromCoord:   lastTransit.FromCoord,
		ToCoord:     chosenCoord,
		DurationSec: transitTime,
		DistanceM:   transitDist,
		Description: fmt.Sprintf("Stay on transit until earlier stop: %s", chosen.Name),
	})

	startWalkNode, _ := findNearestNode(chosenCoord, walkGraph)
	_, walkTime2, walkDist2 := findShortestPathAStar(walkGraph, startWalkNode, destNode, "walk")
	if walkTime2 > 0 {
		chosenWalkTime = walkTime2
		chosenWalkDist = walkDist2
	}
	out = append(out, RouteStep{
		Mode:        "walk_from_transit",
		FromCoord:   chosenCoord,
		ToCoord:     endCoord,
		DurationSec: chosenWalkTime,
		DistanceM:   chosenWalkDist,
		Description: fmt.Sprintf("Walk from %s to destination (%.1f min)", chosen.Name, chosenWalkTime/60),
	})

	return out, nil
}

func ptrNow() *time.Time { t := time.Now(); return &t }
