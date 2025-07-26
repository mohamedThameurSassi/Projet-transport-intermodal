package models

type RouteRequest struct {
	Origin      Location         `json:"origin" binding:"required"`
	Destination Location         `json:"destination" binding:"required"`
	Modes       []TransportMode  `json:"modes" binding:"required"`
	Preferences RoutePreferences `json:"preferences,omitempty"`
	Options     RequestOptions   `json:"options,omitempty"`
}

type ParkingRequest struct {
	Origin         Location `json:"origin" binding:"required"`
	Destination    Location `json:"destination" binding:"required"`
	MaxWalkTime    int      `json:"max_walk_time_minutes" binding:"required,min=1,max=60"`
	MaxResults     *int     `json:"max_results,omitempty"`
	IncludeDetails bool     `json:"include_details,omitempty"`
}

type RequestOptions struct {
	IncludeInstructions bool    `json:"include_instructions,omitempty"`
	IncludeSteps        bool    `json:"include_steps,omitempty"`
	IncludePolyline     bool    `json:"include_polyline,omitempty"`
	Language            *string `json:"language,omitempty"`
}
