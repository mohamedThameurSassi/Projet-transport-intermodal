package routing

type RouteRequest struct {
	StartLat         float64 `json:"startLat"`
	StartLon         float64 `json:"startLon"`
	EndLat           float64 `json:"endLat"`
	EndLon           float64 `json:"endLon"`
	WalkDurationMins float64 `json:"walkDurationMins,omitempty"`
}

// Rich response used by iOS client
type RouteResponse struct {
	Steps             []RouteStep `json:"steps"`
	TotalDistanceM    float64     `json:"totalDistanceM"`
	TotalDurationSec  float64     `json:"totalDurationSec"`
	WalkDistanceM     float64     `json:"walkDistanceM"`
	WalkDurationSec   float64     `json:"walkDurationSec"`
	CarDistanceM      float64     `json:"carDistanceM"`
	CarDurationSec    float64     `json:"carDurationSec"`
	CaloriesBurned    int         `json:"caloriesBurned"`
	CarbonFootprintKg float64     `json:"carbonFootprintKg"`
	// Back-compat hints
	CarOrTransitStart Coordinate `json:"carOrTransitStart"`
	WalkStart         Coordinate `json:"walkStart"`
	WalkEnd           Coordinate `json:"walkEnd"`
}

func PrepareResponse(steps []RouteStep) RouteResponse {
	resp := RouteResponse{Steps: steps}

	for _, step := range steps {
		if step.Mode == "car" || step.Mode == "transit" {
			resp.CarOrTransitStart = step.FromCoord
			break
		}
	}

	walkModes := map[string]bool{"walk": true, "walk_final": true, "walk_to_transit": true, "walk_from_transit": true}
	firstWalkSet := false
	for _, step := range steps {
		// Totals
		resp.TotalDistanceM += step.DistanceM
		resp.TotalDurationSec += step.DurationSec
		if step.Mode == "car" {
			resp.CarDistanceM += step.DistanceM
			resp.CarDurationSec += step.DurationSec
		}
		if walkModes[step.Mode] {
			if !firstWalkSet {
				resp.WalkStart = step.FromCoord
				firstWalkSet = true
			}
			resp.WalkEnd = step.ToCoord
			resp.WalkDistanceM += step.DistanceM
			resp.WalkDurationSec += step.DurationSec
		}
	}

	resp.CaloriesBurned = int((resp.WalkDistanceM / 1000.0) * 50.0)
	resp.CarbonFootprintKg = (resp.CarDistanceM / 1000.0) * 0.21

	return resp
}
