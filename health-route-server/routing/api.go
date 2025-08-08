package routing

type RouteRequest struct {
	StartLat         float64 `json:"startLat"`
	StartLon         float64 `json:"startLon"`
	EndLat           float64 `json:"endLat"`
	EndLon           float64 `json:"endLon"`
	WalkDurationMins float64 `json:"walkDurationMins,omitempty"`
}

type RouteResponse struct {
	CarOrTransitStart Coordinate `json:"carOrTransitStart"`
	WalkStart         Coordinate `json:"walkStart"`
	WalkEnd           Coordinate `json:"walkEnd"`
	WalkDurationSec   float64    `json:"walkDurationSec"`
}

func PrepareResponse(steps []RouteStep) RouteResponse {
	resp := RouteResponse{}

	// Determine first car or transit start
	for _, step := range steps {
		if step.Mode == "car" || step.Mode == "transit" {
			resp.CarOrTransitStart = step.FromCoord
			break
		}
	}

	walkModes := map[string]bool{"walk": true, "walk_final": true, "walk_to_transit": true, "walk_from_transit": true}
	firstWalkSet := false
	for _, step := range steps {
		if walkModes[step.Mode] {
			if !firstWalkSet {
				resp.WalkStart = step.FromCoord
				firstWalkSet = true
			}
			resp.WalkEnd = step.ToCoord // keeps updating to last walk segment end
			resp.WalkDurationSec += step.DurationSec
		}
	}

	return resp
}
