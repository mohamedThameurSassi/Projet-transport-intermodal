package main

import (
	"bufio"
	"context"
	"fmt"
	"github.com/mohamedthameursassi/GoServer/models"
	"github.com/mohamedthameursassi/GoServer/services"
	"os"
	"strconv"
	"strings"
	"time"
)

func main() {
	fmt.Println("=== Walking Points Recommendation Test ===")

	// Initialize walking service
	walkingService := services.NewWalkingService()
	ctx := context.Background()
	scanner := bufio.NewScanner(os.Stdin)

	for {
		fmt.Println("\n--- Enter locations ---")

		destLat := getFloatInput("Destination latitude: ", scanner)
		if destLat == -999 {
			break
		}

		destLng := getFloatInput("Destination longitude: ", scanner)
		if destLng == -999 {
			break
		}

		startLat := getFloatInput("Start latitude: ", scanner)
		if startLat == -999 {
			break
		}

		startLng := getFloatInput("Start longitude: ", scanner)
		if startLng == -999 {
			break
		}

		latestStartLat := getFloatInput("Latest start location latitude: ", scanner)
		if latestStartLat == -999 {
			break
		}

		latestStartLng := getFloatInput("Latest start location longitude: ", scanner)
		if latestStartLng == -999 {
			break
		}

		walkMinutes := getIntInput("Desired walk time (minutes): ", scanner)
		if walkMinutes == -999 {
			break
		}

		// Create locations
		destination := models.Location{
			Latitude:  destLat,
			Longitude: destLng,
		}

		start := models.Location{
			Latitude:  startLat,
			Longitude: startLng,
		}

		latestStartLocation := models.Location{
			Latitude:  latestStartLat,
			Longitude: latestStartLng,
		}

		walktime := time.Duration(walkMinutes) * time.Minute

		fmt.Printf("\n--- Testing with ---\n")
		fmt.Printf("Destination: %.6f, %.6f\n", destination.Latitude, destination.Longitude)
		fmt.Printf("Start: %.6f, %.6f\n", start.Latitude, start.Longitude)
		fmt.Printf("Latest Start: %.6f, %.6f\n", latestStartLocation.Latitude, latestStartLocation.Longitude)
		fmt.Printf("Target walk time: %d minutes\n", walkMinutes)

		// Test the finishRoute method
		fmt.Println("\n--- Calculating recommended walking route ---")
		route, err := walkingService.FinishRoute(destination, start, latestStartLocation, walktime)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
		} else {
			fmt.Printf("\n=== RESULT ===\n")
			fmt.Printf("Distance: %.2f meters\n", route.Distance)
			fmt.Printf("Duration: %.1f minutes\n", route.Duration.Minutes())
			fmt.Printf("Target time: %d minutes\n", walkMinutes)
			fmt.Printf("Difference: %.1f minutes\n", route.Duration.Minutes()-float64(walkMinutes))
		}

		// Test regular route calculation for comparison
		fmt.Println("\n--- For comparison: Direct route ---")
		directRoute, err := walkingService.CalculateRoute(ctx, latestStartLocation, destination, nil)
		if err == nil {
			fmt.Printf("Direct distance: %.2f meters\n", directRoute.Distance)
			fmt.Printf("Direct duration: %.1f minutes\n", directRoute.Duration.Minutes())
		} else {
			fmt.Printf("Direct route error: %v\n", err)
		}

		fmt.Print("\nPress Enter to continue or type 'quit' to exit: ")
		if scanner.Scan() {
			input := strings.TrimSpace(scanner.Text())
			if input == "quit" {
				break
			}
		}
	}

	fmt.Println("Goodbye!")
}

func getFloatInput(prompt string, scanner *bufio.Scanner) float64 {
	for {
		fmt.Print(prompt)
		if scanner.Scan() {
			input := strings.TrimSpace(scanner.Text())
			if input == "quit" {
				return -999
			}
			if val, err := strconv.ParseFloat(input, 64); err == nil {
				return val
			}
			fmt.Println("Invalid input, please try again")
		}
	}
}

func getIntInput(prompt string, scanner *bufio.Scanner) int {
	for {
		fmt.Print(prompt)
		if scanner.Scan() {
			input := strings.TrimSpace(scanner.Text())
			if input == "quit" {
				return -999
			}
			if val, err := strconv.Atoi(input); err == nil {
				return val
			}
			fmt.Println("Invalid input, please try again")
		}
	}
}
