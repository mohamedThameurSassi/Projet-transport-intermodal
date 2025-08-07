package routing

// Node represents a vertex in the transportation graph
type Node struct {
	ID        int64   // Unique identifier for the node
	Latitude  float64 // Geographic latitude in degrees
	Longitude float64 // Geographic longitude in degrees
}

// Edge represents a directed connection between two nodes
type Edge struct {
	FromID     int64    // ID of the starting node
	ToID       int64    // ID of the ending node
	Distance   float64  // Distance in meters
	TravelTime float64  // Travel time in seconds
	Geometry   []string // Optional geometry data (e.g., encoded polyline)
}

// Graph represents a directed graph of transportation nodes and edges
type Graph struct {
	Nodes map[int64]*Node   // Map of node IDs to node objects
	Edges map[int64][]*Edge // Map of node IDs to outgoing edges
}

func NewGraph() *Graph {
	return &Graph{
		Nodes: make(map[int64]*Node),
		Edges: make(map[int64][]*Edge),
	}
}
