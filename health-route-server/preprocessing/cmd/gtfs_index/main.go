package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"

	"health-route-server/preprocessing"
)

type gtfsDump struct {
	StopsByID       map[string]preprocessing.GTFSStop       `json:"stopsByID"`
	TripsByID       map[string]preprocessing.GTFSTrip       `json:"tripsByID"`
	StopTimesByTrip map[string][]preprocessing.GTFSStopTime `json:"stopTimesByTrip"`
	TripsByStopID   map[string][]string                     `json:"tripsByStopID"`
	RouteTripsByDir map[string]map[int][]string             `json:"routeTripsByDir"`
	Summary         map[string]int                          `json:"summary"`
}

func main() {
	var dir string
	var out string
	flag.StringVar(&dir, "dir", "data", "Path to GTFS directory containing stops.txt, trips.txt, stop_times.txt")
	flag.StringVar(&out, "out", "preprocessing/cache/gtfs_index.json", "Path to write JSON dump of GTFS index")
	flag.Parse()

	log.Printf("Loading GTFS from %s...", dir)
	idx, err := preprocessing.LoadGTFS(dir)
	if err != nil {
		log.Fatalf("failed to load GTFS: %v", err)
	}

	dump := gtfsDump{
		StopsByID:       idx.StopsByID,
		TripsByID:       idx.TripsByID,
		StopTimesByTrip: idx.StopTimesByTrip,
		TripsByStopID:   idx.TripsByStopID,
		RouteTripsByDir: idx.RouteTripsByDir,
		Summary: map[string]int{
			"stops":       len(idx.StopsByID),
			"trips":       len(idx.TripsByID),
			"stopTimes":   len(idx.StopTimesByTrip),
			"tripsByStop": len(idx.TripsByStopID),
		},
	}

	if err := os.MkdirAll("preprocessing/cache", 0o755); err != nil {
		log.Fatalf("failed to ensure cache dir: %v", err)
	}

	f, err := os.Create(out)
	if err != nil {
		log.Fatalf("failed to create output file %s: %v", out, err)
	}
	defer f.Close()

	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	if err := enc.Encode(&dump); err != nil {
		log.Fatalf("failed to write JSON: %v", err)
	}

	fmt.Printf("GTFS index written to %s\n", out)
	fmt.Printf("Summary: stops=%d trips=%d tripsWithStopTimes=%d\n",
		len(idx.StopsByID), len(idx.TripsByID), len(idx.StopTimesByTrip))
}
