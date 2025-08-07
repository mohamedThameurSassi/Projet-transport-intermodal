package main

import (
	"encoding/gob"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type JSONGraph struct {
	Metadata struct {
		GeneratedAt string   `json:"generated_at"`
		Title       string   `json:"title"`
		Components  []string `json:"components"`
		NodeCount   int      `json:"node_count"`
		EdgeCount   int      `json:"edge_count"`
	} `json:"metadata"`
	Graph struct {
		Directed   bool `json:"directed"`
		Multigraph bool `json:"multigraph"`
		Graph      struct {
			CreatedDate string `json:"created_date"`
			CreatedWith string `json:"created_with"`
			CRS         string `json:"crs"`
			Simplified  bool   `json:"simplified"`
		} `json:"graph"`
		Nodes []JSONNode `json:"nodes"`
		Links []JSONEdge `json:"links"`
	} `json:"graph"`
}

type JSONNode struct {
	Y           float64     `json:"y"`
	X           float64     `json:"x"`
	StreetCount int         `json:"street_count"`
	Lon         float64     `json:"lon"`
	Lat         float64     `json:"lat"`
	ID          interface{} `json:"id"` // Can be int64 or string
	Type        string      `json:"type,omitempty"`
}

type JSONEdge struct {
	OSMID     interface{} `json:"osmid"`    // Can be int64, array, or string
	Highway   interface{} `json:"highway"`  // Can be string or array
	Lanes     interface{} `json:"lanes"`    // Can be string or array
	Maxspeed  interface{} `json:"maxspeed"` // Can be string or array
	Name      interface{} `json:"name"`     // Can be string or array
	Oneway    interface{} `json:"oneway"`   // Can be bool or array
	Reversed  interface{} `json:"reversed"` // Can be bool or array
	Length    float64     `json:"length"`
	Weight    float64     `json:"weight"`
	Mode      string      `json:"mode"`
	DistanceM float64     `json:"distance_m"`
	Source    interface{} `json:"source"` // Can be int64 or string
	Target    interface{} `json:"target"` // Can be int64 or string
	Key       int         `json:"key"`
}
type Node struct {
	ID        int64   `json:"id"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type Edge struct {
	FromID     int64   `json:"from_id"`
	ToID       int64   `json:"to_id"`
	Distance   float64 `json:"distance"` // Changed from Length to Distance
	TravelTime float64 `json:"travel_time"`
	Name       string  `json:"name"`
}

type Graph struct {
	Nodes map[int64]Node   `json:"nodes"`
	Edges map[int64][]Edge `json:"edges"`
}

func convertID(id interface{}) (int64, error) {
	switch v := id.(type) {
	case float64:
		return int64(v), nil
	case int64:
		return v, nil
	case int:
		return int64(v), nil
	case string:
		return strconv.ParseInt(v, 10, 64)
	case json.Number:
		return v.Int64()
	default:
		return 0, fmt.Errorf("unsupported ID type: %T", id)
	}
}
func convertToString(val interface{}) string {
	switch v := val.(type) {
	case string:
		return v
	case []interface{}:
		parts := make([]string, 0, len(v))
		for _, e := range v {
			parts = append(parts, fmt.Sprintf("%v", e))
		}
		return strings.Join(parts, ",")
	case json.Number:
		return v.String()
	default:
		if v == nil {
			return ""
		}
		return fmt.Sprintf("%v", v)
	}
}

func convertJSONToGOB(inputPath, outputPath string) error {
	f, err := os.Open(inputPath)
	if err != nil {
		return fmt.Errorf("failed to open JSON file %s: %w", inputPath, err)
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	dec.UseNumber()

	var jsonGraph JSONGraph
	if err := dec.Decode(&jsonGraph); err != nil {
		return fmt.Errorf("failed to parse JSON from %s: %w", inputPath, err)
	}

	graph := Graph{
		Nodes: make(map[int64]Node),
		Edges: make(map[int64][]Edge),
	}
	for _, jsonNode := range jsonGraph.Graph.Nodes {
		nodeID, err := convertID(jsonNode.ID)
		if err != nil {
			return fmt.Errorf("failed to convert node ID (%v): %w", jsonNode.ID, err)
		}

		lat := jsonNode.Lat
		lon := jsonNode.Lon
		if lat == 0 && lon == 0 {
			lat = jsonNode.Y
			lon = jsonNode.X
		}

		graph.Nodes[nodeID] = Node{
			ID:        nodeID,
			Latitude:  lat,
			Longitude: lon,
		}
	}

	for _, jsonEdge := range jsonGraph.Graph.Links {
		sourceID, err := convertID(jsonEdge.Source)
		if err != nil {
			return fmt.Errorf("failed to convert source ID (%v): %w", jsonEdge.Source, err)
		}

		targetID, err := convertID(jsonEdge.Target)
		if err != nil {
			return fmt.Errorf("failed to convert target ID (%v): %w", jsonEdge.Target, err)
		}

		edge := Edge{
			FromID:     sourceID,
			ToID:       targetID,
			Distance:   jsonEdge.Length,
			TravelTime: jsonEdge.Weight,
			Name:       convertToString(jsonEdge.Name),
		}

		graph.Edges[sourceID] = append(graph.Edges[sourceID], edge)
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return fmt.Errorf("failed to create output directory for %s: %w", outputPath, err)
	}

	gobFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create GOB file %s: %w", outputPath, err)
	}
	defer gobFile.Close()

	encoder := gob.NewEncoder(gobFile)
	if err := encoder.Encode(graph); err != nil {
		return fmt.Errorf("failed to encode GOB to %s: %w", outputPath, err)
	}

	fmt.Printf("Successfully converted %s to %s\n", inputPath, outputPath)
	fmt.Printf("Nodes: %d, Edges: %d\n", len(graph.Nodes), len(jsonGraph.Graph.Links))

	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run json_to_gob.go <input_json_file> [output_gob_file]")
		os.Exit(1)
	}

	inputPath := os.Args[1]

	var outputPath string
	if len(os.Args) > 2 {
		outputPath = os.Args[2]
	} else {
		ext := filepath.Ext(inputPath)
		base := strings.TrimSuffix(filepath.Base(inputPath), ext)
		outputPath = filepath.Join(filepath.Dir(inputPath), base+".gob")
	}

	if err := convertJSONToGOB(inputPath, outputPath); err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
}
