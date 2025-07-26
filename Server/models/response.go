package models

import "time"

type ApiResponse struct {
	Success   bool        `json:"success"`
	Data      interface{} `json:"data,omitempty"`
	Error     *ApiError   `json:"error,omitempty"`
	Meta      *MetaData   `json:"meta,omitempty"`
	RequestID string      `json:"request_id"`
}

type ApiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
}

type MetaData struct {
	ProcessTime   string   `json:"process_time_ms"`
	ApiVersion    string   `json:"api_version"`
	ResultCount   *int     `json:"result_count,omitempty"`
	TotalDistance *float64 `json:"total_distance_km,omitempty"`
	TotalTime     *string  `json:"total_time,omitempty"`
}

type RouteResponse struct {
	Routes []Route `json:"routes"`
	Count  int     `json:"count"`
}

type ParkingResponse struct {
	ParkingOptions []ParkingOption `json:"parking_options"`
	Count          int             `json:"count"`
}

type ParkingOption struct {
	Route        Route         `json:"route"`
	ParkingSpot  Location      `json:"parking_spot"`
	WalkingTime  time.Duration `json:"walking_time"`
	DrivingTime  time.Duration `json:"driving_time"`
	TotalTime    time.Duration `json:"total_time"`
	Optimization string        `json:"optimization_reason,omitempty"`
}
