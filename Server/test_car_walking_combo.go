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
	fmt.Println("=== Enhanced Car + Walking Multimodal Testing ===")
	fmt.Println("This test showcases the optimization features of your routing service")
	fmt.Println()

	scanner := bufio.NewScanner(os.Stdin)
	routingService := services.NewRoutingService()

	for {
		fmt.Println("\nChoose a test scenario:")
		fmt.Println("1. Quick test with sample Montreal coordinates")
		fmt.Println("2. Custom coordinates input")
		fmt.Println("3. Test different walking time preferences")
		fmt.Println("4. Comprehensive optimization showcase")
		fmt.Println("5. Exit")
		fmt.Print("Enter your choice (1-5): ")

		scanner.Scan()
		choice := strings.TrimSpace(scanner.Text())

		switch choice {
		case "1":
			testWithSampleCoordinates(routingService)
		case "2":
			testWithCustomCoordinates(routingService, scanner)
		case "3":
			testWalkingTimePreferences(routingService, scanner)
		case "4":
			testOptimizationShowcase(routingService, scanner)
		case "5":
			fmt.Println("Goodbye!")
			return
		default:
			fmt.Println("Invalid choice. Please try again.")
		}
	}
}

func testWithSampleCoordinates(routingService *services.RoutingService) {
	fmt.Println("\n=== Quick Test with Montreal Sample Coordinates ===")

	// Montreal downtown area coordinates
	origin := models.Location{
		Latitude:  45.5017,
		Longitude: -73.5673,
		Address:   "Downtown Montreal (Sample)",
	}

	destination := models.Location{
		Latitude:  45.5088,
		Longitude: -73.5878,
		Address:   "Montreal West (Sample)",
	}

	fmt.Printf("Origin: %s (%.4f, %.4f)\n", origin.Address, origin.Latitude, origin.Longitude)
	fmt.Printf("Destination: %s (%.4f, %.4f)\n", destination.Address, destination.Latitude, destination.Longitude)

	testCarWalkingCombo(routingService, origin, destination, 10, 8)
}

func testWithCustomCoordinates(routingService *services.RoutingService, scanner *bufio.Scanner) {
	fmt.Println("\n=== Custom Coordinates Test ===")

	origin := getLocationInput(scanner, "origin")
	if origin == nil {
		return
	}

	destination := getLocationInput(scanner, "destination")
	if destination == nil {
		return
	}

	maxWalkTime := getIntInput("Max walking time (minutes, default 10): ", scanner, 10)
	preferredWalkTime := getIntInput("Preferred walking time (minutes, default 8): ", scanner, 8)

	testCarWalkingCombo(routingService, *origin, *destination, maxWalkTime, preferredWalkTime)
}

func testWalkingTimePreferences(routingService *services.RoutingService, scanner *bufio.Scanner) {
	fmt.Println("\n=== Walking Time Preferences Test ===")
	fmt.Println("This test shows how different walking preferences affect route selection")

	// Use sample coordinates
	origin := models.Location{Latitude: 45.5017, Longitude: -73.5673, Address: "Sample Origin"}
	destination := models.Location{Latitude: 45.5088, Longitude: -73.5878, Address: "Sample Destination"}

	preferences := []struct {
		maxWalk, preferredWalk int
		description            string
	}{
		{15, 5, "Short preferred walk (5 min), high max (15 min)"},
		{10, 10, "Same preferred and max walk (10 min each)"},
		{20, 15, "Long preferred walk (15 min), very high max (20 min)"},
	}

	for i, pref := range preferences {
		fmt.Printf("\n--- Test %d: %s ---\n", i+1, pref.description)
		testCarWalkingCombo(routingService, origin, destination, pref.maxWalk, pref.preferredWalk)

		if i < len(preferences)-1 {
			fmt.Print("\nPress Enter to continue to next test...")
			scanner.Scan()
		}
	}
}

func testOptimizationShowcase(routingService *services.RoutingService, scanner *bufio.Scanner) {
	fmt.Println("\n=== Comprehensive Optimization Showcase ===")
	fmt.Println("This test demonstrates all optimization features:")
	fmt.Println("- Parking location generation around destination")
	fmt.Println("- Distance-based parking selection from origin")
	fmt.Println("- Composite scoring (60% car time + 40% walking preference)")
	fmt.Println("- Route ranking and optimization details")
	fmt.Println()

	origin := getLocationInput(scanner, "origin")
	if origin == nil {
		return
	}

	destination := getLocationInput(scanner, "destination")
	if destination == nil {
		return
	}

	maxWalkTime := getIntInput("Max walking time (minutes): ", scanner, 10)
	preferredWalkTime := getIntInput("Preferred walking time (minutes): ", scanner, 8)

	fmt.Println("\n🔍 DETAILED OPTIMIZATION PROCESS:")

	// Show parking location generation
	walkingService := services.NewWalkingService()
	fmt.Printf("\n1. Generating parking locations within %d minutes of destination...\n", maxWalkTime)
	allParkingLocations := walkingService.FindAccessibleParkingLocations(*destination, maxWalkTime*60)
	fmt.Printf("   Generated %d parking locations\n", len(allParkingLocations))

	// Show closest parking selection
	fmt.Printf("\n2. Selecting 5 closest parking locations to origin...\n")
	closestParkingLocations := walkingService.SelectClosestParkingLocations(*origin, allParkingLocations)
	for i, parking := range closestParkingLocations {
		fmt.Printf("   %d. %s (%.4f, %.4f)\n", i+1, parking.Address, parking.Latitude, parking.Longitude)
	}

	// Show full routing with optimization details
	fmt.Printf("\n3. Calculating optimized routes...\n")
	testCarWalkingCombo(routingService, *origin, *destination, maxWalkTime, preferredWalkTime)
}

func testCarWalkingCombo(routingService *services.RoutingService, origin, destination models.Location, maxWalkTime, preferredWalkTime int) {
	req := models.RouteRequest{
		Origin:      origin,
		Destination: destination,
		Modes:       []models.TransportMode{models.Car, models.Walking},
		Preferences: models.RoutePreferences{
			MaxWalkTime:       maxWalkTime,
			PreferredWalkTime: preferredWalkTime,
		},
	}

	fmt.Println("\nCalculating multimodal routes...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	routes, err := routingService.CalculateRoutes(ctx, req)
	if err != nil {
		fmt.Printf("❌ Error: %v\n", err)
		return
	}

	if len(routes) == 0 {
		fmt.Println("❌ No routes found")
		return
	}

	fmt.Printf("\n✅ Found %d optimized route(s):\n", len(routes))
	fmt.Println("=" + strings.Repeat("=", 80))

	for i, route := range routes {
		fmt.Printf("\n🚗 Route %d: %s\n", i+1, route.ID)
		fmt.Printf("📊 Total Time: %v (%.1f minutes)\n", route.TotalTime, route.TotalTime.Minutes())
		fmt.Printf("📏 Total Distance: %.2f km\n", route.Distance/1000)
		fmt.Printf("🚀 Modes: %v\n", route.Modes)

		var carTime, walkingTime time.Duration
		fmt.Println("\n📋 Route Segments:")
		for j, segment := range route.Segments {
			modeIcon := "🚶‍♂️"
			if segment.Mode == models.Car {
				modeIcon = "🚗"
				carTime = segment.Duration
			} else {
				walkingTime = segment.Duration
			}

			fmt.Printf("   %d. %s %s\n", j+1, modeIcon, *segment.Instructions)
			fmt.Printf("      ⏱️  Duration: %v (%.1f min) | 📏 Distance: %.2f km\n",
				segment.Duration, segment.Duration.Minutes(), segment.Distance/1000)
		}

		// Show optimization scoring details
		walkingMinutes := int(walkingTime.Minutes())
		walkingDiff := abs(walkingMinutes - preferredWalkTime)

		fmt.Printf("\n📈 Optimization Analysis:\n")
		fmt.Printf("   🚗 Car time: %.1f minutes\n", carTime.Minutes())
		fmt.Printf("   🚶‍♂️ Walking time: %.1f minutes (target: %d min, diff: %d min)\n",
			walkingTime.Minutes(), preferredWalkTime, walkingDiff)

		carScore := carTime.Minutes() * 0.6
		walkingScore := float64(walkingDiff) * 0.4
		compositeScore := carScore + walkingScore

		fmt.Printf("   📊 Composite Score: %.2f (car: %.2f + walk_diff: %.2f)\n",
			compositeScore, carScore, walkingScore)
		fmt.Printf("   🎯 Lower composite score = better route\n")

		if i < len(routes)-1 {
			fmt.Println("\n" + strings.Repeat("-", 80))
		}
	}

	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Printf("🏆 Best route selected: Route 1 (lowest composite score)\n")
}

func getLocationInput(scanner *bufio.Scanner, locationType string) *models.Location {
	fmt.Printf("\nEnter %s coordinates:\n", locationType)

	lat := getFloatInput("Latitude: ", scanner, 0)
	lng := getFloatInput("Longitude: ", scanner, 0)

	fmt.Print("Address (optional): ")
	scanner.Scan()
	address := strings.TrimSpace(scanner.Text())
	if address == "" {
		address = fmt.Sprintf("%s location", locationType)
	}

	return &models.Location{
		Latitude:  lat,
		Longitude: lng,
		Address:   address,
	}
}

func getFloatInput(prompt string, scanner *bufio.Scanner, defaultVal float64) float64 {
	for {
		fmt.Print(prompt)
		scanner.Scan()
		input := strings.TrimSpace(scanner.Text())

		if input == "" && defaultVal != 0 {
			return defaultVal
		}

		if val, err := strconv.ParseFloat(input, 64); err == nil {
			return val
		}
		fmt.Println("Invalid input, please try again")
	}
}

func getIntInput(prompt string, scanner *bufio.Scanner, defaultVal int) int {
	for {
		fmt.Print(prompt)
		scanner.Scan()
		input := strings.TrimSpace(scanner.Text())

		if input == "" && defaultVal != 0 {
			return defaultVal
		}

		if val, err := strconv.Atoi(input); err == nil {
			return val
		}
		fmt.Println("Invalid input, please try again")
	}
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
