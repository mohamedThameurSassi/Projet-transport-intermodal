package routing

type RouteRequest struct {
	StartLat         float64 `json:"startLat"`
	StartLon         float64 `json:"startLon"`
	EndLat           float64 `json:"endLat"`
	EndLon           float64 `json:"endLon"`
	WalkDurationMins float64 `json:"walkDurationMins,omitempty"`
}

type RouteResponse struct {
	Steps            []RouteStep `json:"steps"`
	Error            string      `json:"error,omitempty"`
	TotalDistanceM   float64     `json:"totalDistanceM"`
	TotalDurationSec float64     `json:"totalDurationSec"`
	WalkDistanceM    float64     `json:"walkDistanceM"`
	WalkDurationSec  float64     `json:"walkDurationSec"`
	CarDistanceM     float64     `json:"carDistanceM"`
	CarDurationSec   float64     `json:"carDurationSec"`
}

func PrepareResponse(steps []RouteStep) RouteResponse {
	resp := RouteResponse{
		Steps: steps,
	}

	for _, step := range steps {
		resp.TotalDistanceM += step.DistanceM
		resp.TotalDurationSec += step.DurationSec

		switch step.Mode {
		case "car":
			resp.CarDistanceM += step.DistanceM
			resp.CarDurationSec += step.DurationSec
		case "walk_final", "walk_to_transit", "walk_from_transit":
			resp.WalkDistanceM += step.DistanceM
			resp.WalkDurationSec += step.DurationSec
		}
	}

	return resp
}
