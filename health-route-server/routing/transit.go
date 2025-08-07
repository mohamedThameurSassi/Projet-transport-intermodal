package routing

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
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

	params.Set("alternatives", "true")
	params.Set("units", "metric")

	if departureTime != nil {
		params.Set("departure_time", fmt.Sprintf("%d", departureTime.Unix()))
	} else {
		params.Set("departure_time", "now")
	}

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
	result := html

	replacements := [][]string{
		{"<b>", ""},
		{"</b>", ""},
		{"<div>", " "},
		{"</div>", ""},
		{"<div style=\"font-size:0.9em\">", " - "},
		{"&nbsp;", " "},
		{"&amp;", "&"},
		{"&lt;", "<"},
		{"&gt;", ">"},
		{"<wbr/>", ""},
		{"<wbr>", ""},
	}

	for _, pair := range replacements {
		result = strings.ReplaceAll(result, pair[0], pair[1])
	}

	result = strings.TrimSpace(result)
	result = strings.Join(strings.Fields(result), " ")

	return result
}

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
		nil,
		maxWalkMinutes,
	)

	if err != nil {
		return nil, err
	}

	for i := range steps {
		if steps[i].Mode == "walk" {
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
