package models

type TransportMode string

const (
	Bixi          TransportMode = "bixi"
	Biking        TransportMode = "biking"
	Car           TransportMode = "car"
	PublicTransit TransportMode = "public_transport"
	Walking       TransportMode = "walking"
)
