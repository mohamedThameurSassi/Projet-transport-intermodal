package main

import (
	"encoding/gob"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"health-route-server/preprocessing"
	"health-route-server/routing"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

// Graph structures for pre-loaded routing data (matching the stored GOB format)
type Node struct {
	ID          int64   `json:"id"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	StreetCount int     `json:"streetCount,omitempty"`
}

type TransportMode int

const (
	Unknown TransportMode = iota
	Car
	Walking
	Biking
	Bixi
	PublicTransit
)

type Edge struct {
	FromID            int64         `json:"fromId"`
	ToID              int64         `json:"toId"`
	Distance          float64       `json:"distance"`   // Changed from Length to Distance
	MaxSpeed          float64       `json:"maxSpeed"`   // km/h
	TravelTime        float64       `json:"travelTime"` // seconds
	TrafficMultiplier float64       `json:"trafficMultiplier"`
	Mode              TransportMode `json:"mode"`
	Name              string        `json:"name,omitempty"`
}

type Graph struct {
	Nodes map[int64]Node   `json:"nodes"`
	Edges map[int64][]Edge `json:"edges"`
	Modes []TransportMode  `json:"modes,omitempty"`
}

var (
	carGraph  *Graph
	bikeGraph *Graph
	walkGraph *Graph
	gtfsGraph *Graph

	// Cached routing graphs (converted once)
	routingCarGraph  *routing.Graph
	routingWalkGraph *routing.Graph
)

type OSRMConfig struct {
	CarURL  string
	BikeURL string
	WalkURL string
	GTFSUrl string
}

var osrmConfig = OSRMConfig{
	CarURL:  "http://localhost:5000",
	BikeURL: "http://localhost:5001",
	WalkURL: "http://localhost:5002",
	GTFSUrl: "http://localhost:5003",
}

type OSRMRoute struct {
	Distance float64 `json:"distance"`
	Duration float64 `json:"duration"`
	Geometry string  `json:"geometry"`
}

type OSRMResponse struct {
	Routes []OSRMRoute `json:"routes"`
	Code   string      `json:"code"`
}

type LocationPoint struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Address   *string `json:"address,omitempty"`
}

type TripRequest struct {
	Origin             LocationPoint `json:"origin"`
	Destination        LocationPoint `json:"destination"`
	PreferredTransport string        `json:"preferredTransport"`
	RequestTime        time.Time     `json:"requestTime"`
}

type RouteSegment struct {
	TransportType string        `json:"transportType"`
	Duration      float64       `json:"duration"`
	Distance      float64       `json:"distance"`
	Instructions  string        `json:"instructions"`
	StartLocation LocationPoint `json:"startLocation"`
	EndLocation   LocationPoint `json:"endLocation"`
	Polyline      *string       `json:"polyline,omitempty"`
}

type RouteOption struct {
	ID                string         `json:"id"`
	Segments          []RouteSegment `json:"segments"`
	TotalDuration     float64        `json:"totalDuration"`
	TotalDistance     float64        `json:"totalDistance"`
	EstimatedCalories int            `json:"estimatedCalories"`
	HealthScore       int            `json:"healthScore"`
	CarbonFootprint   float64        `json:"carbonFootprint"`
}

type TripResponse struct {
	OriginalRoute      RouteOption   `json:"originalRoute"`
	HealthAlternatives []RouteOption `json:"healthAlternatives"`
	RequestID          string        `json:"requestId"`
}

func loadGraphs() error {
	dataDir := "data"

	var err error

	carGraph, err = loadGraph(filepath.Join(dataDir, "car_graph.gob"))
	if err != nil {
		return fmt.Errorf("failed to load car graph: %v", err)
	}

	bikeGraph, err = loadGraph(filepath.Join(dataDir, "bike_graph.gob"))
	if err != nil {
		return fmt.Errorf("failed to load bike graph: %v", err)
	}

	walkGraph, err = loadGraph(filepath.Join(dataDir, "walk_graph.gob"))
	if err != nil {
		return fmt.Errorf("failed to load walk graph: %v", err)
	}

	gtfsGraph, err = loadGraph(filepath.Join(dataDir, "gtfs_graph.gob"))
	if err != nil {
		return fmt.Errorf("failed to load gtfs graph: %v", err)
	}

	log.Println("Successfully loaded all pre-generated graphs")
	return nil
}

func loadGraph(filename string) (*Graph, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	decoder := gob.NewDecoder(file)
	var graph Graph
	if err := decoder.Decode(&graph); err != nil {
		return nil, err
	}

	log.Printf("Loaded graph from %s: %d nodes, %d edges", filename, len(graph.Nodes), len(graph.Edges))
	return &graph, nil
}

func routeWithGraph(from, to LocationPoint, graph *Graph) (*OSRMRoute, error) {
	if graph == nil {
		return nil, fmt.Errorf("graph not loaded")
	}

	startNode, err := findNearestNode(from, graph)
	if err != nil {
		return nil, fmt.Errorf("could not find start node: %v", err)
	}

	endNode, err := findNearestNode(to, graph)
	if err != nil {
		return nil, fmt.Errorf("could not find end node: %v", err)
	}

	route, err := findShortestPath(startNode, endNode, graph)
	if err != nil {
		return nil, fmt.Errorf("could not find route: %v", err)
	}

	return route, nil
}

func findNearestNode(point LocationPoint, graph *Graph) (int64, error) {
	var nearestNodeID int64
	minDistance := math.Inf(1)

	for nodeID, node := range graph.Nodes {
		dist := calculateDistance(point, LocationPoint{Latitude: node.Latitude, Longitude: node.Longitude})
		if dist < minDistance {
			minDistance = dist
			nearestNodeID = nodeID
		}
	}

	if minDistance == math.Inf(1) {
		return 0, fmt.Errorf("no nodes found in graph")
	}

	return nearestNodeID, nil
}

func findShortestPath(startID, endID int64, graph *Graph) (*OSRMRoute, error) {
	if startID == endID {
		return &OSRMRoute{Distance: 0, Duration: 0, Geometry: ""}, nil
	}

	startNode := graph.Nodes[startID]
	endNode := graph.Nodes[endID]

	distance := calculateDistance(
		LocationPoint{Latitude: startNode.Latitude, Longitude: startNode.Longitude},
		LocationPoint{Latitude: endNode.Latitude, Longitude: endNode.Longitude},
	) * 1000

	duration := distance / (30.0 / 3.6)

	return &OSRMRoute{
		Distance: distance,
		Duration: duration,
		Geometry: "",
	}, nil
}

func (g *Graph) toRoutingGraph() *routing.Graph {
	rg := routing.NewGraph()

	for id, node := range g.Nodes {
		rg.Nodes[id] = &routing.Node{
			ID:        node.ID,
			Latitude:  node.Latitude,
			Longitude: node.Longitude,
		}
	}

	for fromNodeID, edges := range g.Edges {
		if rg.Edges[fromNodeID] == nil {
			rg.Edges[fromNodeID] = make([]*routing.Edge, 0)
		}
		for _, edge := range edges {
			rg.Edges[fromNodeID] = append(rg.Edges[fromNodeID], &routing.Edge{
				FromID:     edge.FromID,
				ToID:       edge.ToID,
				Distance:   edge.Distance,
				TravelTime: edge.TravelTime,
				Geometry:   []string{edge.Name},
			})
		}
	}

	return rg
}

func handleCarWalkRoute(c *gin.Context) {
	log.Println("=== Received car+walk route request ===")

	var req routing.RouteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("ERROR: Failed to parse request: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Request details: Start(%.6f, %.6f) -> End(%.6f, %.6f), Walk duration: %.1f mins",
		req.StartLat, req.StartLon, req.EndLat, req.EndLon, req.WalkDurationMins)

	if req.WalkDurationMins == 0 {
		req.WalkDurationMins = 20 // 20 minutes default
		log.Printf("Using default walk duration: %.1f minutes", req.WalkDurationMins)
	}

	// Validate cached graphs
	if routingCarGraph == nil || routingWalkGraph == nil {
		log.Println("ERROR: Cached routing graphs not initialized")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "routing graphs not initialized"})
		return
	}

	log.Println("Starting route calculation using cached graphs...")
	steps := routing.PlanCarPlusLastWalk(
		routing.Coordinate{Lat: req.StartLat, Lon: req.StartLon},
		routing.Coordinate{Lat: req.EndLat, Lon: req.EndLon},
		routingWalkGraph,
		routingCarGraph,
		req.WalkDurationMins,
	)

	log.Printf("Route calculation completed, found %d steps", len(steps))

	resp := routing.PrepareResponse(steps)
	log.Printf("Sending response: car/transit start=(%.6f,%.6f) walkStart=(%.6f,%.6f) walkEnd=(%.6f,%.6f) walkDur=%.1fs",
		resp.CarOrTransitStart.Lat, resp.CarOrTransitStart.Lon,
		resp.WalkStart.Lat, resp.WalkStart.Lon,
		resp.WalkEnd.Lat, resp.WalkEnd.Lon,
		resp.WalkDurationSec,
	)
	c.JSON(http.StatusOK, resp)
	log.Println("=== Car+walk route request completed ===")
}

func handleTransitRoute(c *gin.Context) {
	log.Println("=== Received transit route request ===")

	var req routing.RouteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("ERROR: Failed to parse request: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Request details: Start(%.6f, %.6f) -> End(%.6f, %.6f), Max walk: %.1f mins",
		req.StartLat, req.StartLon, req.EndLat, req.EndLon, req.WalkDurationMins)

	if req.WalkDurationMins == 0 {
		req.WalkDurationMins = 15 // 15 minutes default walking
		log.Printf("Using default walk duration: %.1f minutes", req.WalkDurationMins)
	}

	log.Println("Starting Google Maps transit route calculation...")
	steps, err := routing.PlanTransitPlusWalk(
		routing.Coordinate{Lat: req.StartLat, Lon: req.StartLon},
		routing.Coordinate{Lat: req.EndLat, Lon: req.EndLon},
		req.WalkDurationMins,
	)

	if err != nil {
		log.Printf("ERROR: Transit routing failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Transit routing failed: %v", err)})
		return
	}

	log.Printf("Transit route calculation completed, found %d steps", len(steps))

	resp := routing.PrepareResponse(steps)
	log.Printf("Sending response: transit start=(%.6f,%.6f) walkStart=(%.6f,%.6f) walkEnd=(%.6f,%.6f) walkDur=%.1fs",
		resp.CarOrTransitStart.Lat, resp.CarOrTransitStart.Lon,
		resp.WalkStart.Lat, resp.WalkStart.Lon,
		resp.WalkEnd.Lat, resp.WalkEnd.Lon,
		resp.WalkDurationSec,
	)
	c.JSON(http.StatusOK, resp)
	log.Println("=== Transit route request completed ===")
}

func main() {

	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using default environment variables")
	}

	log.Println("Loading pre-generated graphs...")
	if err := loadGraphs(); err != nil {
		log.Fatalf("Failed to load required graph data: %v", err)
	}
	log.Println("All graphs loaded successfully!")

	// Convert to routing graphs once (heavy allocation avoided per request)
	log.Println("Converting graphs to routing format (one-time)...")
	routingCarGraph = carGraph.toRoutingGraph()
	routingWalkGraph = walkGraph.toRoutingGraph()
	log.Printf("Cached routing graphs ready. Car nodes: %d, Walk nodes: %d", len(routingCarGraph.Nodes), len(routingWalkGraph.Nodes))

	// Load GTFS preprocessing once
	if _, err := preprocessing.LoadGTFSIndexOnce("data"); err != nil { // assuming GTFS txt files in data/
		log.Printf("Warning: failed to load GTFS index: %v", err)
	} else {
		log.Println("GTFS index loaded successfully at startup")
	}

	r := gin.Default()

	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"*"}
	r.Use(cors.New(config))

	r.POST("/route/car-walk", handleCarWalkRoute)

	r.POST("/route/transit", handleTransitRoute)

	r.POST("/api/health-route", handleHealthRoute)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "healthy"})
	})

	log.Println("Health Route Server starting on :8080")
	log.Println("Using pre-loaded graphs for fast routing")

	if err := r.Run(":8080"); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}

func getOSRMRoute(from, to LocationPoint, transportType string) (*OSRMRoute, error) {
	var graph *Graph

	switch transportType {
	case "car", "driving":
		graph = carGraph
	case "bike", "biking":
		graph = bikeGraph
	case "walk", "walking":
		graph = walkGraph
	case "gtfs", "transit":
		graph = gtfsGraph
	}

	if graph != nil {
		log.Printf("Using pre-loaded graph for %s routing", transportType)
		return routeWithGraph(from, to, graph)
	}

	log.Printf("Falling back to OSRM API for %s routing", transportType)

	var baseURL string

	switch transportType {
	case "car", "driving":
		baseURL = osrmConfig.CarURL
	case "bike", "biking":
		baseURL = osrmConfig.BikeURL
	case "walk", "walking":
		baseURL = osrmConfig.WalkURL
	case "gtfs", "transit":
		return getGTFSRoute(from, to)
	default:
		baseURL = osrmConfig.CarURL
	}

	coordinates := fmt.Sprintf("%.6f,%.6f;%.6f,%.6f",
		from.Longitude, from.Latitude, to.Longitude, to.Latitude)

	requestURL := fmt.Sprintf("%s/route/v1/driving/%s?overview=full&geometries=polyline",
		baseURL, coordinates)

	log.Printf("OSRM Request: %s", requestURL)

	resp, err := http.Get(requestURL)
	if err != nil {
		return nil, fmt.Errorf("OSRM request failed: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read OSRM response: %v", err)
	}

	var osrmResp OSRMResponse
	if err := json.Unmarshal(body, &osrmResp); err != nil {
		return nil, fmt.Errorf("failed to parse OSRM response: %v", err)
	}

	if osrmResp.Code != "Ok" || len(osrmResp.Routes) == 0 {
		return nil, fmt.Errorf("OSRM returned no valid routes: %s", osrmResp.Code)
	}

	return &osrmResp.Routes[0], nil
}

func getGTFSRoute(from, to LocationPoint) (*OSRMRoute, error) {

	params := url.Values{}
	params.Set("from", fmt.Sprintf("%.6f,%.6f", from.Latitude, from.Longitude))
	params.Set("to", fmt.Sprintf("%.6f,%.6f", to.Latitude, to.Longitude))
	params.Set("time", time.Now().Format("15:04"))
	params.Set("date", time.Now().Format("2006-01-02"))

	requestURL := fmt.Sprintf("%s/plan?%s", osrmConfig.GTFSUrl, params.Encode())

	log.Printf("GTFS Request: %s", requestURL)

	resp, err := http.Get(requestURL)
	if err != nil {
		return nil, fmt.Errorf("GTFS request failed: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read GTFS response: %v", err)
	}

	log.Printf("GTFS Response: %s", string(body))

	distance := calculateDistance(from, to) * 1000
	duration := distance / (30.0 / 3.6)

	return &OSRMRoute{
		Distance: distance,
		Duration: duration,
		Geometry: "",
	}, nil
}

func handleHealthRoute(c *gin.Context) {
	var req TripRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log.Printf("Received trip request from (%.6f, %.6f) to (%.6f, %.6f) using %s",
		req.Origin.Latitude, req.Origin.Longitude,
		req.Destination.Latitude, req.Destination.Longitude,
		req.PreferredTransport)

	originalRoute, err := generateOriginalRouteOSRM(req)
	if err != nil {
		log.Printf("Error generating original route: %v", err)
		distance := calculateDistance(req.Origin, req.Destination)
		original := generateOriginalRoute(req, distance)
		originalRoute = &original
	}

	healthAlternatives, err := generateHealthAlternativesOSRM(req)
	if err != nil {
		log.Printf("Error generating health alternatives: %v", err)
		distance := calculateDistance(req.Origin, req.Destination)
		healthAlternatives = generateHealthAlternatives(req, distance)
	}

	response := TripResponse{
		OriginalRoute:      *originalRoute,
		HealthAlternatives: healthAlternatives,
		RequestID:          fmt.Sprintf("trip_%d", time.Now().Unix()),
	}

	c.JSON(http.StatusOK, response)
}

func generateOriginalRouteOSRM(req TripRequest) (*RouteOption, error) {
	transportType := req.PreferredTransport
	if transportType == "gtfs" {
		transportType = "transit"
	}

	osrmRoute, err := getOSRMRoute(req.Origin, req.Destination, req.PreferredTransport)
	if err != nil {
		return nil, err
	}

	calories := 0
	healthScore := 1
	carbonFootprint := 0.0

	switch req.PreferredTransport {
	case "car":
		calories = 0
		healthScore = 1
		carbonFootprint = (osrmRoute.Distance / 1000) * 0.21 // kg CO2 per km
	case "gtfs":
		calories = int((osrmRoute.Distance / 1000) * 5) // Small amount from walking to/from stops
		healthScore = 3
		carbonFootprint = (osrmRoute.Distance / 1000) * 0.05 // kg CO2 per km
	}

	return &RouteOption{
		ID: "original",
		Segments: []RouteSegment{
			{
				TransportType: transportType,
				Duration:      osrmRoute.Duration,
				Distance:      osrmRoute.Distance,
				Instructions:  fmt.Sprintf("Take %s to destination", transportType),
				StartLocation: req.Origin,
				EndLocation:   req.Destination,
				Polyline:      &osrmRoute.Geometry,
			},
		},
		TotalDuration:     osrmRoute.Duration,
		TotalDistance:     osrmRoute.Distance,
		EstimatedCalories: calories,
		HealthScore:       healthScore,
		CarbonFootprint:   carbonFootprint,
	}, nil
}

func generateHealthAlternativesOSRM(req TripRequest) ([]RouteOption, error) {
	alternatives := []RouteOption{}

	if req.PreferredTransport == "car" {
		driveWalkRoute, err := generateDriveWalkAlternative(req)
		if err == nil {
			alternatives = append(alternatives, *driveWalkRoute)
		} else {
			log.Printf("Failed to generate drive+walk alternative: %v", err)
		}
	}

	if req.PreferredTransport == "gtfs" {
		transitWalkRoute, err := generateTransitWalkAlternative(req)
		if err == nil {
			alternatives = append(alternatives, *transitWalkRoute)
		} else {
			log.Printf("Failed to generate transit+walk alternative: %v", err)
		}
	}

	distanceKm := calculateDistance(req.Origin, req.Destination)
	if distanceKm < 10.0 {
		bikeRoute, err := generateBikeAlternative(req)
		if err == nil {
			alternatives = append(alternatives, *bikeRoute)
		} else {
			log.Printf("Failed to generate bike alternative: %v", err)
		}
	}

	if distanceKm < 5.0 {
		walkRoute, err := generateWalkAlternative(req)
		if err == nil {
			alternatives = append(alternatives, *walkRoute)
		} else {
			log.Printf("Failed to generate walk alternative: %v", err)
		}
	}

	return alternatives, nil
}

func generateDriveWalkAlternative(req TripRequest) (*RouteOption, error) {
	walkingMinutes := 25.0
	walkingSpeed := 5.0 / 3.6                             // 5 km/h in m/s
	walkingDistance := walkingMinutes * 60 * walkingSpeed // meters

	totalDistance := calculateDistance(req.Origin, req.Destination) * 1000 // meters
	ratio := (totalDistance - walkingDistance) / totalDistance

	parkingPoint := LocationPoint{
		Latitude:  req.Origin.Latitude + (req.Destination.Latitude-req.Origin.Latitude)*ratio,
		Longitude: req.Origin.Longitude + (req.Destination.Longitude-req.Origin.Longitude)*ratio,
	}

	// Get driving route to parking point
	driveRoute, err := getOSRMRoute(req.Origin, parkingPoint, "car")
	if err != nil {
		return nil, fmt.Errorf("failed to get drive route: %v", err)
	}

	// Get walking route from parking point to destination
	walkRoute, err := getOSRMRoute(parkingPoint, req.Destination, "walking")
	if err != nil {
		return nil, fmt.Errorf("failed to get walk route: %v", err)
	}

	// Calculate health metrics
	walkingCalories := int((walkRoute.Distance / 1000) * 50) // 50 cal/km
	drivingCarbon := (driveRoute.Distance / 1000) * 0.21     // kg CO2/km

	return &RouteOption{
		ID: "drive_and_walk",
		Segments: []RouteSegment{
			{
				TransportType: "driving",
				Duration:      driveRoute.Duration,
				Distance:      driveRoute.Distance,
				Instructions:  fmt.Sprintf("Drive %.1f km to parking area", driveRoute.Distance/1000),
				StartLocation: req.Origin,
				EndLocation:   parkingPoint,
				Polyline:      &driveRoute.Geometry,
			},
			{
				TransportType: "walking",
				Duration:      walkRoute.Duration,
				Distance:      walkRoute.Distance,
				Instructions: fmt.Sprintf("Walk %.1f km (%.0f minutes) to destination",
					walkRoute.Distance/1000, walkRoute.Duration/60),
				StartLocation: parkingPoint,
				EndLocation:   req.Destination,
				Polyline:      &walkRoute.Geometry,
			},
		},
		TotalDuration:     driveRoute.Duration + walkRoute.Duration,
		TotalDistance:     driveRoute.Distance + walkRoute.Distance,
		EstimatedCalories: walkingCalories,
		HealthScore:       6, // Better than pure driving
		CarbonFootprint:   drivingCarbon,
	}, nil
}

// Generate Transit + Walk alternative
func generateTransitWalkAlternative(req TripRequest) (*RouteOption, error) {
	// Similar logic to drive+walk but with transit
	walkingMinutes := 20.0
	walkingSpeed := 5.0 / 3.6 // m/s
	walkingDistance := walkingMinutes * 60 * walkingSpeed

	totalDistance := calculateDistance(req.Origin, req.Destination) * 1000
	ratio := (totalDistance - walkingDistance) / totalDistance

	transitEndPoint := LocationPoint{
		Latitude:  req.Origin.Latitude + (req.Destination.Latitude-req.Origin.Latitude)*ratio,
		Longitude: req.Origin.Longitude + (req.Destination.Longitude-req.Origin.Longitude)*ratio,
	}

	transitRoute, err := getOSRMRoute(req.Origin, transitEndPoint, "gtfs")
	if err != nil {
		return nil, fmt.Errorf("failed to get transit route: %v", err)
	}

	walkRoute, err := getOSRMRoute(transitEndPoint, req.Destination, "walking")
	if err != nil {
		return nil, fmt.Errorf("failed to get walk route: %v", err)
	}

	walkingCalories := int((walkRoute.Distance / 1000) * 50)
	transitCarbon := (transitRoute.Distance / 1000) * 0.05

	return &RouteOption{
		ID: "transit_and_walk",
		Segments: []RouteSegment{
			{
				TransportType: "transit",
				Duration:      transitRoute.Duration,
				Distance:      transitRoute.Distance,
				Instructions:  fmt.Sprintf("Take public transit %.1f km", transitRoute.Distance/1000),
				StartLocation: req.Origin,
				EndLocation:   transitEndPoint,
				Polyline:      &transitRoute.Geometry,
			},
			{
				TransportType: "walking",
				Duration:      walkRoute.Duration,
				Distance:      walkRoute.Distance,
				Instructions: fmt.Sprintf("Walk %.1f km (%.0f minutes) to destination",
					walkRoute.Distance/1000, walkRoute.Duration/60),
				StartLocation: transitEndPoint,
				EndLocation:   req.Destination,
				Polyline:      &walkRoute.Geometry,
			},
		},
		TotalDuration:     transitRoute.Duration + walkRoute.Duration,
		TotalDistance:     transitRoute.Distance + walkRoute.Distance,
		EstimatedCalories: walkingCalories,
		HealthScore:       7,
		CarbonFootprint:   transitCarbon,
	}, nil
}

// Generate pure biking alternative
func generateBikeAlternative(req TripRequest) (*RouteOption, error) {
	bikeRoute, err := getOSRMRoute(req.Origin, req.Destination, "biking")
	if err != nil {
		return nil, err
	}

	bikingCalories := int((bikeRoute.Distance / 1000) * 40) // 40 cal/km

	return &RouteOption{
		ID: "biking",
		Segments: []RouteSegment{
			{
				TransportType: "biking",
				Duration:      bikeRoute.Duration,
				Distance:      bikeRoute.Distance,
				Instructions:  fmt.Sprintf("Bike %.1f km to destination", bikeRoute.Distance/1000),
				StartLocation: req.Origin,
				EndLocation:   req.Destination,
				Polyline:      &bikeRoute.Geometry,
			},
		},
		TotalDuration:     bikeRoute.Duration,
		TotalDistance:     bikeRoute.Distance,
		EstimatedCalories: bikingCalories,
		HealthScore:       9,
		CarbonFootprint:   0,
	}, nil
}

// Generate pure walking alternative
func generateWalkAlternative(req TripRequest) (*RouteOption, error) {
	walkRoute, err := getOSRMRoute(req.Origin, req.Destination, "walking")
	if err != nil {
		return nil, err
	}

	walkingCalories := int((walkRoute.Distance / 1000) * 50) // 50 cal/km

	return &RouteOption{
		ID: "walking",
		Segments: []RouteSegment{
			{
				TransportType: "walking",
				Duration:      walkRoute.Duration,
				Distance:      walkRoute.Distance,
				Instructions:  fmt.Sprintf("Walk %.1f km to destination", walkRoute.Distance/1000),
				StartLocation: req.Origin,
				EndLocation:   req.Destination,
				Polyline:      &walkRoute.Geometry,
			},
		},
		TotalDuration:     walkRoute.Duration,
		TotalDistance:     walkRoute.Distance,
		EstimatedCalories: walkingCalories,
		HealthScore:       8,
		CarbonFootprint:   0,
	}, nil
}

func generateOriginalRoute(req TripRequest, distance float64) RouteOption {
	var transportType string
	var duration float64
	var calories int
	var carbonFootprint float64
	var healthScore int

	switch req.PreferredTransport {
	case "car":
		transportType = "driving"
		duration = distance / 50 * 3600   // Assume 50 km/h average speed
		calories = 0                      // No calories burned driving
		carbonFootprint = distance * 0.21 // kg CO2 per km for average car
		healthScore = 1
	case "gtfs":
		transportType = "transit"
		duration = distance / 30 * 3600   // Assume 30 km/h average for transit
		calories = int(distance * 0.05)   // Small amount from walking to/from stops
		carbonFootprint = distance * 0.05 // Much lower for public transit
		healthScore = 3
	default:
		transportType = "driving"
		duration = distance / 50 * 3600
		calories = 0
		carbonFootprint = distance * 0.21
		healthScore = 1
	}

	return RouteOption{
		ID: "original",
		Segments: []RouteSegment{
			{
				TransportType: transportType,
				Duration:      duration,
				Distance:      distance * 1000, // Convert to meters
				Instructions:  fmt.Sprintf("Take %s to destination", transportType),
				StartLocation: req.Origin,
				EndLocation:   req.Destination,
			},
		},
		TotalDuration:     duration,
		TotalDistance:     distance * 1000,
		EstimatedCalories: calories,
		HealthScore:       healthScore,
		CarbonFootprint:   carbonFootprint,
	}
}

func generateHealthAlternatives(req TripRequest, distance float64) []RouteOption {
	alternatives := []RouteOption{}

	// Alternative 1: Walking + Transit (if distance > 2km)
	if distance > 2.0 {
		walkingDistance := 1.0 // 1km walking
		transitDistance := distance - walkingDistance

		walkingDuration := walkingDistance / 5 * 3600  // 5 km/h walking speed
		transitDuration := transitDistance / 30 * 3600 // 30 km/h transit

		totalDuration := walkingDuration + transitDuration
		walkingCalories := int(walkingDistance * 50) // ~50 calories per km walking

		alternatives = append(alternatives, RouteOption{
			ID: "walking_transit",
			Segments: []RouteSegment{
				{
					TransportType: "walking",
					Duration:      walkingDuration,
					Distance:      walkingDistance * 1000,
					Instructions:  "Walk to transit stop",
					StartLocation: req.Origin,
					EndLocation: LocationPoint{
						Latitude:  req.Origin.Latitude + 0.005,
						Longitude: req.Origin.Longitude + 0.005,
					},
				},
				{
					TransportType: "transit",
					Duration:      transitDuration,
					Distance:      transitDistance * 1000,
					Instructions:  "Take public transit",
					StartLocation: LocationPoint{
						Latitude:  req.Origin.Latitude + 0.005,
						Longitude: req.Origin.Longitude + 0.005,
					},
					EndLocation: req.Destination,
				},
			},
			TotalDuration:     totalDuration,
			TotalDistance:     distance * 1000,
			EstimatedCalories: walkingCalories,
			HealthScore:       7,
			CarbonFootprint:   transitDistance * 0.05,
		})
	}

	// Alternative 2: Biking (if distance < 10km)
	if distance < 10.0 {
		bikingDuration := distance / 15 * 3600 // 15 km/h biking speed
		bikingCalories := int(distance * 40)   // ~40 calories per km biking

		alternatives = append(alternatives, RouteOption{
			ID: "biking",
			Segments: []RouteSegment{
				{
					TransportType: "biking",
					Duration:      bikingDuration,
					Distance:      distance * 1000,
					Instructions:  "Bike to destination",
					StartLocation: req.Origin,
					EndLocation:   req.Destination,
				},
			},
			TotalDuration:     bikingDuration,
			TotalDistance:     distance * 1000,
			EstimatedCalories: bikingCalories,
			HealthScore:       9,
			CarbonFootprint:   0, // No emissions for biking
		})
	}

	// Alternative 3: Walking (if distance < 5km)
	if distance < 5.0 {
		walkingDuration := distance / 5 * 3600 // 5 km/h walking speed
		walkingCalories := int(distance * 50)  // ~50 calories per km walking

		alternatives = append(alternatives, RouteOption{
			ID: "walking",
			Segments: []RouteSegment{
				{
					TransportType: "walking",
					Duration:      walkingDuration,
					Distance:      distance * 1000,
					Instructions:  "Walk to destination",
					StartLocation: req.Origin,
					EndLocation:   req.Destination,
				},
			},
			TotalDuration:     walkingDuration,
			TotalDistance:     distance * 1000,
			EstimatedCalories: walkingCalories,
			HealthScore:       8,
			CarbonFootprint:   0, // No emissions for walking
		})
	}

	return alternatives
}

// Calculate distance between two points using Haversine formula
func calculateDistance(point1, point2 LocationPoint) float64 {
	const R = 6371 // Earth's radius in kilometers

	lat1 := point1.Latitude * math.Pi / 180
	lat2 := point2.Latitude * math.Pi / 180
	deltaLat := (point2.Latitude - point1.Latitude) * math.Pi / 180
	deltaLon := (point2.Longitude - point1.Longitude) * math.Pi / 180

	a := math.Sin(deltaLat/2)*math.Sin(deltaLat/2) +
		math.Cos(lat1)*math.Cos(lat2)*
			math.Sin(deltaLon/2)*math.Sin(deltaLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return R * c // Distance in kilometers
}
