package graphs_go

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"

	"github.com/mohamedthameursassi/GoServer/models"
)

// Node represents a graph node (intersection).
type Node struct {
	ID          int64
	Latitude    float64
	Longitude   float64
	StreetCount int
}

type Edge struct {
	FromID            int64
	ToID              int64
	Length            float64
	MaxSpeed          float64
	TravelTime        float64
	TrafficMultiplier float64
	Mode              models.TransportMode
	Name              string
}

type Graph struct {
	Nodes map[int64]Node
	Edges map[int64][]Edge
	Modes []models.TransportMode `json:"-"`
}

func parseSpeed(speed interface{}) float64 {
	switch v := speed.(type) {
	case float64:
		return v
	case string:
		re := regexp.MustCompile(`\d+`)
		match := re.FindString(v)
		if match != "" {
			if parsed, err := strconv.ParseFloat(match, 64); err == nil {
				return parsed
			}
		}
		return 50.0
	case []interface{}:
		if len(v) > 0 {
			return parseSpeed(v[0])
		}
		return 50.0
	default:
		return 50.0
	}
}

// parseID converts various ID formats to int64
func parseID(id interface{}) int64 {
	switch v := id.(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	case string:
		// Try to extract numeric part from strings like "stop_123", "bixi_456"
		re := regexp.MustCompile(`\d+`)
		match := re.FindString(v)
		if match != "" {
			if parsed, err := strconv.ParseInt(match, 10, 64); err == nil {
				return parsed
			}
		}
		// If no numeric part found, hash the string to get a unique int64
		hash := int64(0)
		for _, c := range v {
			hash = hash*31 + int64(c)
		}
		if hash < 0 {
			hash = -hash
		}
		return hash
	default:
		return 0
	}
}

func LoadGraphFromJSON(data []byte) (*Graph, error) {
	var wrapped struct {
		Graph struct {
			Nodes []struct {
				ID          interface{} `json:"id"`
				X           float64     `json:"x"`
				Y           float64     `json:"y"`
				StreetCount int         `json:"street_count"`
			} `json:"nodes"`
			Links []struct {
				Source            interface{} `json:"source"`
				Target            interface{} `json:"target"`
				Length            float64     `json:"length"`
				MaxSpeed          interface{} `json:"maxspeed"`
				TravelTime        float64     `json:"travel_time"`
				TrafficMultiplier float64     `json:"traffic_multiplier"`
			} `json:"links"`
		} `json:"graph"`
	}

	if err := json.Unmarshal(data, &wrapped); err != nil {
		return nil, fmt.Errorf("failed to parse graph JSON: %v", err)
	}

	// Convert to Graph
	g := &Graph{
		Nodes: make(map[int64]Node),
		Edges: make(map[int64][]Edge),
	}

	for _, n := range wrapped.Graph.Nodes {
		nodeID := parseID(n.ID)
		g.Nodes[nodeID] = Node{
			ID:          nodeID,
			Latitude:    n.Y,
			Longitude:   n.X,
			StreetCount: n.StreetCount,
		}
	}

	for _, e := range wrapped.Graph.Links {
		sourceID := parseID(e.Source)
		targetID := parseID(e.Target)
		maxSpeed := parseSpeed(e.MaxSpeed)
		g.Edges[sourceID] = append(g.Edges[sourceID], Edge{
			FromID:            sourceID,
			ToID:              targetID,
			Length:            e.Length,
			MaxSpeed:          maxSpeed,
			TravelTime:        e.TravelTime,
			TrafficMultiplier: e.TrafficMultiplier,
			Name:              "", // Not present in JSON
		})
	}

	return g, nil
}
