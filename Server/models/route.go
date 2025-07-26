package models

import "time"

type Route struct {
	ID          string          `json:"id"`
	Origin      Location        `json:"origin"`
	Destination Location        `json:"destination"`
	Segments    []RouteSegment  `json:"segments"`
	TotalTime   time.Duration   `json:"total_time"`
	Distance    float64         `json:"distance"`
	Modes       []TransportMode `json:"modes"`
	Duration    time.Duration   `json:"duration"`
}

type RouteSegment struct {
	Mode         TransportMode `json:"mode"`
	Origin       Location      `json:"origin"`
	Destination  Location      `json:"destination"`
	Duration     time.Duration `json:"duration"`
	Distance     float64       `json:"distance"`
	Instructions *string       `json:"instructions,omitempty"`
	Steps        []Step        `json:"steps,omitempty"`
	Polyline     *string       `json:"polyline,omitempty"`
}

type Step struct {
	Instructions string  `json:"instructions"`
	Distance     float64 `json:"distance"`
	Duration     float64 `json:"duration"`
	Maneuver     string  `json:"maneuver"`
}
