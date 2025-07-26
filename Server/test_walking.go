package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mohamedthameursassi/GoServer/models"
	"github.com/mohamedthameursassi/GoServer/services"
)

func main() {
	fmt.Println("=== Walking Service Test with OpenStreetMap Integration ===")
	fmt.Println()

	// Create walking service
	walkingService := services.NewWalkingService()
	scanner := bufio.NewScanner(os.Stdin)

	for {
		fmt.Println("\nChoose an option:")
		fmt.Println("1. Test walking route calculation")
		fmt.Println("2. Test parking location finder")
		fmt.Println("3. Test multimodal routing (car + walking)")
		fmt.Println("4. Exit")
		fmt.Print("Enter your choice (1-4): ")

		scanner.Scan()
		choice := strings.TrimSpace(scanner.Text())

		switch choice {
		case "1":
			testWalkingRoute(walkingService, scanner)
		case "2":
			testParkingFinder(walkingService, scanner)
		case "3":
			testMultimodalRouting(scanner)
		case "4":
			fmt.Println("Goodbye!")
			return
		default:
			fmt.Println("Invalid choice. Please try again.")
		}
	}
}

func testWalkingRoute(walkingService *services.WalkingService, scanner *bufio.Scanner) {
	fmt.Println("\n=== Walking Route Test ===")

	// Get origin coordinates
	origin := getLocationInput(scanner, "origin")
	if origin == nil {
		return
	}

	// Get destination coordinates
	destination := getLocationInput(scanner, "destination")
	if destination == nil {
		return
	}

	// Calculate route
	fmt.Println("\nCalculating walking route...")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	route, err := walkingService.CalculateRoute(ctx, *origin, *destination)
	if err != nil {
		fmt.Printf("Error calculating route: %v\n", err)
		return
	}

	// Display results
	fmt.Println("\n--- Route Results ---")
	fmt.Printf("Route ID: %s\n", route.ID)
	fmt.Printf("Total Distance: %.2f meters (%.2f km)\n", route.Distance, route.Distance/1000)
	fmt.Printf("Total Time: %v (%.0f minutes)\n", route.TotalTime, route.TotalTime.Minutes())
	fmt.Printf("Transport Modes: %v\n", route.Modes)

	if len(route.Segments) > 0 {
		segment := route.Segments[0]
		fmt.Printf("Instructions: %s\n", segment.Instructions)
		if segment.Polyline != "" {
			fmt.Printf("Polyline available: %d characters\n", len(segment.Polyline))
		}
	}
}

func testParkingFinder(walkingService *services.WalkingService, scanner *bufio.Scanner) {
	fmt.Println("\n=== Parking Location Finder Test ===")

	// Get destination coordinates
	destination := getLocationInput(scanner, "destination")
	if destination == nil {
		return
	}

	// Get max walking time
	fmt.Print("Enter max walking time in minutes (default 10): ")
	scanner.Scan()
	timeStr := strings.TrimSpace(scanner.Text())
	maxWalkingTime := 10
	if timeStr != "" {
		if t, err := strconv.Atoi(timeStr); err == nil {
			maxWalkingTime = t
		}
	}

	// Find parking locations
	fmt.Printf("\nFinding parking locations within %d minutes walk...\n", maxWalkingTime)
	locations := walkingService.FindAccessibleParkingLocations(*destination, maxWalkingTime*60)

	// Display results
	fmt.Printf("\n--- Found %d parking locations ---\n", len(locations))
	for i, location := range locations {
		fmt.Printf("%d. %s\n", i+1, location.Address)
		fmt.Printf("   Coordinates: %.6f, %.6f\n", location.Latitude, location.Longitude)
	}
}

func testMultimodalRouting(scanner *bufio.Scanner) {
	fmt.Println("\n=== Multimodal Routing Test (Car + Walking) ===")

	// Get origin coordinates
	origin := getLocationInput(scanner, "origin")
	if origin == nil {
		return
	}

	// Get destination coordinates
	destination := getLocationInput(scanner, "destination")
	if destination == nil {
		return
	}

	// Get max walking time
	fmt.Print("Enter max walking time in minutes (default 10): ")
	scanner.Scan()
	timeStr := strings.TrimSpace(scanner.Text())
	maxWalkingTime := 10
	if timeStr != "" {
		if t, err := strconv.Atoi(timeStr); err == nil {
			maxWalkingTime = t
		}
	}

	// Create routing service
	routingService := services.NewRoutingService()

	// Create route request
	req := models.RouteRequest{
		Origin:      *origin,
		Destination: *destination,
		Modes:       []models.TransportMode{models.Car, models.Walking},
		Preferences: models.RoutePreferences{
			MaxWalkTime: maxWalkingTime,
		},
	}

	fmt.Println("\nCalculating multimodal routes...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	routes, err := routingService.CalculateRoutes(ctx, req)
	if err != nil {
		fmt.Printf("Error calculating routes: %v\n", err)
		return
	}

	fmt.Printf("\n--- Found %d routes ---\n", len(routes))
	for i, route := range routes {
		fmt.Printf("\n%d. Route: %s\n", i+1, route.ID)
		fmt.Printf("   Total Time: %v (%.0f minutes)\n", route.TotalTime, route.TotalTime.Minutes())
		fmt.Printf("   Total Distance: %.2f meters (%.2f km)\n", route.Distance, route.Distance/1000)
		fmt.Printf("   Modes: %v\n", route.Modes)

		for j, segment := range route.Segments {
			fmt.Printf("   Segment %d (%s): %s\n", j+1, segment.Mode, segment.Instructions)
			fmt.Printf("      Duration: %v, Distance: %.0f meters\n", segment.Duration, segment.Distance)
		}
	}
}

func getLocationInput(scanner *bufio.Scanner, locationType string) *models.Location {
	fmt.Printf("\nEnter %s coordinates:\n", locationType)

	// Get latitude
	fmt.Print("Latitude: ")
	scanner.Scan()
	latStr := strings.TrimSpace(scanner.Text())
	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil {
		fmt.Printf("Invalid latitude: %v\n", err)
		return nil
	}

	// Get longitude
	fmt.Print("Longitude: ")
	scanner.Scan()
	lngStr := strings.TrimSpace(scanner.Text())
	lng, err := strconv.ParseFloat(lngStr, 64)
	if err != nil {
		fmt.Printf("Invalid longitude: %v\n", err)
		return nil
	}

	// Optional address
	fmt.Print("Address (optional): ")
	scanner.Scan()
	address := strings.TrimSpace(scanner.Text())

	return &models.Location{
		Latitude:  lat,
		Longitude: lng,
		Address:   address,
	}
}
