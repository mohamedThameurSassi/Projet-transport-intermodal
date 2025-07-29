package graphs_go

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mohamedthameursassi/GoServer/models"
)

// equalPath compares two slices of node IDs for equality.
func equalPath(a, b []int64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestSimpleAStar(t *testing.T) {
	g := &Graph{
		Nodes: map[int64]Node{
			1: {ID: 1, Latitude: 0, Longitude: 0, StreetCount: 0},
			2: {ID: 2, Latitude: 0, Longitude: 1, StreetCount: 0},
			3: {ID: 3, Latitude: 0, Longitude: 2, StreetCount: 0},
		},
		Edges: map[int64][]Edge{
			1: {{FromID: 1, ToID: 2, Length: 100, MaxSpeed: 50, TravelTime: 10, Mode: models.Car, TrafficMultiplier: 1}},
			2: {{FromID: 2, ToID: 3, Length: 200, MaxSpeed: 50, TravelTime: 20, Mode: models.Car, TrafficMultiplier: 1}},
		},
		Modes: []models.TransportMode{models.Car},
	}

	path, err := g.AStar(1, 3)
	if err != nil {
		t.Fatalf("AStar returned error: %v", err)
	}
	expected := []int64{1, 2, 3}
	if !equalPath(path, expected) {
		t.Errorf("expected path %v, got %v", expected, path)
	}
}

func TestNamedGraphsAStar(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("could not get working directory: %v", err)
	}
	graphsDir := filepath.Join(cwd, "..", "data", "graphs")

	graphs, err := LoadGraphsFromDirectory(graphsDir)
	if err != nil {
		t.Fatalf("failed to load graphs from %s: %v", graphsDir, err)
	}

	names := []string{"car_graph", "walk_graph", "bixi_graph", "car_bike_graph", "car_bixi_graph", "car_walk_graph"}
	for _, name := range names {
		name := name
		g, ok := graphs[name]
		if !ok {
			t.Fatalf("graph %s not found in %s", name, graphsDir)
		}

		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if name == "bixi_graph" {
				t.Skip("Skipping bixi_graph as stations are isolated nodes without edges")
				return
			}

			var start, end int64
			for id := range g.Nodes {
				start = id
				break
			}
			for id := range g.Nodes {
				if id != start {
					end = id
					break
				}
			}

			path, err := g.AStar(start, end)
			if err != nil {
				t.Errorf("%s: AStar error: %v", name, err)
				return
			}

			if len(path) < 2 {
				t.Errorf("%s: path too short: %v", name, path)
			}
		})
	}
}
