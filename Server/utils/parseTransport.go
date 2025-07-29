package utils

import (
	"strings"

	"github.com/mohamedthameursassi/GoServer/models"
)

func ParseTransportMode(input string) models.TransportMode {
	switch strings.ToLower(input) {
	case "car":
		return models.Car
	case "bixi":
		return models.Bixi
	case "biking", "bike":
		return models.Biking
	case "walking", "walk":
		return models.Walking
	case "publictransit", "transit":
		return models.PublicTransit
	default:
		return models.Unknown
	}
}
