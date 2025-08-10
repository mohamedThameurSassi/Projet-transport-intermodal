package main

import (
	"encoding/gob"
	"fmt"
	"log"
	"math"
	"net/http"
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
	walkGraph *Graph

	routingCarGraph  *routing.Graph
	routingWalkGraph *routing.Graph
)

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

	walkGraph, err = loadGraph(filepath.Join(dataDir, "walk_graph.gob"))
	if err != nil {
		return fmt.Errorf("failed to load walk graph: %v", err)
	}

	log.Println("Successfully loaded custom graphs for car and walk routing")
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

	log.Println("Starting health-optimized transit route calculation...")

	// Try the health-optimized version first (gets off transit earlier to walk more)
	steps, err := routing.PlanTransitEarlierStopPlusWalk(
		routing.Coordinate{Lat: req.StartLat, Lon: req.StartLon},
		routing.Coordinate{Lat: req.EndLat, Lon: req.EndLon},
		req.WalkDurationMins,
		routingWalkGraph,
	)

	// If that fails, fall back to regular transit routing
	if err != nil {
		log.Printf("Health-optimized transit failed (%v), falling back to regular transit", err)
		steps, err = routing.PlanTransitPlusWalk(
			routing.Coordinate{Lat: req.StartLat, Lon: req.StartLon},
			routing.Coordinate{Lat: req.EndLat, Lon: req.EndLon},
			req.WalkDurationMins,
		)
	}

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
	log.Printf("Cached routing graphs ready. Car nodes: %d, Walk nodes: %d",
		len(routingCarGraph.Nodes), len(routingWalkGraph.Nodes))

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

	// Generate original route using our custom algorithms
	distance := calculateDistance(req.Origin, req.Destination)
	originalRoute := generateOriginalRoute(req, distance)

	// Generate health alternatives using our custom algorithms
	healthAlternatives := generateHealthAlternatives(req, distance)

	response := TripResponse{
		OriginalRoute:      originalRoute,
		HealthAlternatives: healthAlternatives,
		RequestID:          fmt.Sprintf("trip_%d", time.Now().Unix()),
	}

	c.JSON(http.StatusOK, response)
}

// (car-bike endpoint and handler removed during revert)

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
		calories = int(distance * 5)      // Small amount from walking to/from stops
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

	// Alternative 1: Car + Walking (if original transport is car)
	if req.PreferredTransport == "car" {
		walkingDistance := 1.0 // 1km walking
		carDistance := distance - walkingDistance

		if carDistance > 0 {
			walkingDuration := walkingDistance / 5 * 3600 // 5 km/h walking speed
			carDuration := carDistance / 50 * 3600        // 50 km/h car speed
			totalDuration := walkingDuration + carDuration
			walkingCalories := int(walkingDistance * 50) // ~50 calories per km walking

			// Calculate parking point
			ratio := carDistance / distance
			parkingPoint := LocationPoint{
				Latitude:  req.Origin.Latitude + (req.Destination.Latitude-req.Origin.Latitude)*ratio,
				Longitude: req.Origin.Longitude + (req.Destination.Longitude-req.Origin.Longitude)*ratio,
			}

			alternatives = append(alternatives, RouteOption{
				ID: "car_and_walk",
				Segments: []RouteSegment{
					{
						TransportType: "driving",
						Duration:      carDuration,
						Distance:      carDistance * 1000,
						Instructions:  fmt.Sprintf("Drive %.1f km to parking area", carDistance),
						StartLocation: req.Origin,
						EndLocation:   parkingPoint,
					},
					{
						TransportType: "walking",
						Duration:      walkingDuration,
						Distance:      walkingDistance * 1000,
						Instructions: fmt.Sprintf("Walk %.1f km (%.0f minutes) to destination",
							walkingDistance, walkingDuration/60),
						StartLocation: parkingPoint,
						EndLocation:   req.Destination,
					},
				},
				TotalDuration:     totalDuration,
				TotalDistance:     distance * 1000,
				EstimatedCalories: walkingCalories,
				HealthScore:       6,
				CarbonFootprint:   carDistance * 0.21, // kg CO2 per km for driving portion
			})
		}
	}

	// Alternative 2: Transit + Walking (if original transport is gtfs)
	if req.PreferredTransport == "gtfs" {
		walkingDistance := 1.0 // 1km walking
		transitDistance := distance - walkingDistance

		if transitDistance > 0 {
			walkingDuration := walkingDistance / 5 * 3600  // 5 km/h walking speed
			transitDuration := transitDistance / 30 * 3600 // 30 km/h transit speed
			totalDuration := walkingDuration + transitDuration
			walkingCalories := int(walkingDistance * 50) // ~50 calories per km walking

			// Calculate transit end point
			ratio := transitDistance / distance
			transitEndPoint := LocationPoint{
				Latitude:  req.Origin.Latitude + (req.Destination.Latitude-req.Origin.Latitude)*ratio,
				Longitude: req.Origin.Longitude + (req.Destination.Longitude-req.Origin.Longitude)*ratio,
			}

			alternatives = append(alternatives, RouteOption{
				ID: "transit_and_walk",
				Segments: []RouteSegment{
					{
						TransportType: "transit",
						Duration:      transitDuration,
						Distance:      transitDistance * 1000,
						Instructions:  fmt.Sprintf("Take public transit %.1f km", transitDistance),
						StartLocation: req.Origin,
						EndLocation:   transitEndPoint,
					},
					{
						TransportType: "walking",
						Duration:      walkingDuration,
						Distance:      walkingDistance * 1000,
						Instructions: fmt.Sprintf("Walk %.1f km (%.0f minutes) to destination",
							walkingDistance, walkingDuration/60),
						StartLocation: transitEndPoint,
						EndLocation:   req.Destination,
					},
				},
				TotalDuration:     totalDuration,
				TotalDistance:     distance * 1000,
				EstimatedCalories: walkingCalories,
				HealthScore:       7,
				CarbonFootprint:   transitDistance * 0.05, // kg CO2 per km for transit portion
			})
		}
	}

	// Alternative 3: Biking (if distance < 10km)
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
					Instructions:  fmt.Sprintf("Bike %.1f km to destination", distance),
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

	// Alternative 4: Walking (if distance < 5km)
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
					Instructions:  fmt.Sprintf("Walk %.1f km to destination", distance),
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
