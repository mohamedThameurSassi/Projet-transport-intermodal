package models

type RoutePreferences struct {
	OptimizeFor       OptimizationType `json:"optimize_for,omitempty"`
	MaxWalkTime       int              `json:"max_walk_time_minutes,omitempty"`
	PreferredWalkTime int              `json:"preferred_walk_time_minutes,omitempty"`
	PreferredBikeTime int              `json:"preferred_bike_time_minutes,omitempty"`
	MaxBixiTime       int              `json:"max_bixi_time_minutes,omitempty"`
	AvoidHighways     bool             `json:"avoid_highways,omitempty"`
	AvoidTolls        bool             `json:"avoid_tolls,omitempty"`
	WalkingSpeed      *float64         `json:"walking_speed_kmh,omitempty"`
}

type OptimizationType string

const (
	OptimizeTime     OptimizationType = "time"
	OptimizeDistance OptimizationType = "distance"
	OptimizeCost     OptimizationType = "cost"
	OptimizeComfort  OptimizationType = "comfort"
)
