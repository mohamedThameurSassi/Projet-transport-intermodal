package preprocessing

import (
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type GTFSStop struct {
	ID            string
	Name          string
	Lat           float64
	Lon           float64
	ParentStation string
}

type GTFSStopTime struct {
	TripID       string
	StopID       string
	StopSequence int
}

type GTFSTrip struct {
	ID          string
	RouteID     string
	DirectionID int // 0/1
}

type GTFSIndex struct {
	StopsByID       map[string]GTFSStop
	TripsByID       map[string]GTFSTrip
	StopTimesByTrip map[string][]GTFSStopTime   // sorted by StopSequence asc
	TripsByStopID   map[string][]string         // stop_id -> []trip_id (contains that stop)
	RouteTripsByDir map[string]map[int][]string // route_id -> dir -> []trip_id
}

var gtfsIndex *GTFSIndex

type Coordinate struct{ Lat, Lon float64 }

func toRadians(deg float64) float64 { return deg * math.Pi / 180 }

func haversineDistance(c1, c2 Coordinate) float64 {
	phi1 := toRadians(c1.Lat)
	phi2 := toRadians(c2.Lat)
	deltaPhi := toRadians(c2.Lat - c1.Lat)
	deltaLambda := toRadians(c2.Lon - c1.Lon)
	a := math.Sin(deltaPhi/2)*math.Sin(deltaPhi/2) + math.Cos(phi1)*math.Cos(phi2)*math.Sin(deltaLambda/2)*math.Sin(deltaLambda/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	// return meters
	return 6371.0 * c * 1000
}

// LoadGTFS builds a minimal, fast in-memory index from a GTFS directory.
// Required files: stops.txt, trips.txt, stop_times.txt
func LoadGTFS(dir string) (*GTFSIndex, error) {
	stopsPath := filepath.Join(dir, "stops.txt")
	tripsPath := filepath.Join(dir, "trips.txt")
	stopTimesPath := filepath.Join(dir, "stop_times.txt")

	idx := &GTFSIndex{
		StopsByID:       make(map[string]GTFSStop),
		TripsByID:       make(map[string]GTFSTrip),
		StopTimesByTrip: make(map[string][]GTFSStopTime),
		TripsByStopID:   make(map[string][]string),
		RouteTripsByDir: make(map[string]map[int][]string),
	}

	// 1) stops.txt
	if err := loadStops(stopsPath, idx); err != nil {
		return nil, err
	}

	// 2) trips.txt
	if err := loadTrips(tripsPath, idx); err != nil {
		return nil, err
	}

	// 3) stop_times.txt
	if err := loadStopTimes(stopTimesPath, idx); err != nil {
		return nil, err
	}

	// sort stop_times per trip by stop_sequence once
	for tripID := range idx.StopTimesByTrip {
		st := idx.StopTimesByTrip[tripID]
		sort.Slice(st, func(i, j int) bool { return st[i].StopSequence < st[j].StopSequence })
		idx.StopTimesByTrip[tripID] = st
	}

	return idx, nil
}

func loadStops(path string, idx *GTFSIndex) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open stops.txt: %w", err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.FieldsPerRecord = -1
	header, err := r.Read()
	if err != nil {
		return fmt.Errorf("read stops header: %w", err)
	}
	h := headerIndex(header)

	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("read stops row: %w", err)
		}

		get := func(k string) string {
			i, ok := h[k]
			if !ok || i >= len(row) {
				return ""
			}
			return row[i]
		}
		lat, _ := strconv.ParseFloat(get("stop_lat"), 64)
		lon, _ := strconv.ParseFloat(get("stop_lon"), 64)

		s := GTFSStop{
			ID:            get("stop_id"),
			Name:          get("stop_name"),
			Lat:           lat,
			Lon:           lon,
			ParentStation: get("parent_station"),
		}
		if s.ID != "" {
			idx.StopsByID[s.ID] = s
		}
	}
	return nil
}

func loadTrips(path string, idx *GTFSIndex) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open trips.txt: %w", err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.FieldsPerRecord = -1
	header, err := r.Read()
	if err != nil {
		return fmt.Errorf("read trips header: %w", err)
	}
	h := headerIndex(header)

	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("read trips row: %w", err)
		}

		get := func(k string) string {
			i, ok := h[k]
			if !ok || i >= len(row) {
				return ""
			}
			return row[i]
		}
		dir := 0
		if v := strings.TrimSpace(get("direction_id")); v != "" {
			d, _ := strconv.Atoi(v)
			dir = d
		}
		trip := GTFSTrip{
			ID:          get("trip_id"),
			RouteID:     get("route_id"),
			DirectionID: dir,
		}
		if trip.ID == "" {
			continue
		}

		idx.TripsByID[trip.ID] = trip

		if _, ok := idx.RouteTripsByDir[trip.RouteID]; !ok {
			idx.RouteTripsByDir[trip.RouteID] = map[int][]string{}
		}
		idx.RouteTripsByDir[trip.RouteID][trip.DirectionID] =
			append(idx.RouteTripsByDir[trip.RouteID][trip.DirectionID], trip.ID)
	}
	return nil
}

func loadStopTimes(path string, idx *GTFSIndex) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open stop_times.txt: %w", err)
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.FieldsPerRecord = -1
	header, err := r.Read()
	if err != nil {
		return fmt.Errorf("read stop_times header: %w", err)
	}
	h := headerIndex(header)

	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("read stop_times row: %w", err)
		}

		get := func(k string) string {
			i, ok := h[k]
			if !ok || i >= len(row) {
				return ""
			}
			return row[i]
		}
		seq, _ := strconv.Atoi(strings.TrimSpace(get("stop_sequence")))
		tripID := get("trip_id")
		stopID := get("stop_id")
		if tripID == "" || stopID == "" {
			continue
		}

		st := GTFSStopTime{
			TripID:       tripID,
			StopID:       stopID,
			StopSequence: seq,
		}
		idx.StopTimesByTrip[tripID] = append(idx.StopTimesByTrip[tripID], st)
		idx.TripsByStopID[stopID] = append(idx.TripsByStopID[stopID], tripID)
	}
	return nil
}

func headerIndex(hdr []string) map[string]int {
	m := make(map[string]int, len(hdr))
	for i, k := range hdr {
		m[strings.TrimSpace(k)] = i
	}
	return m
}

func LoadGTFSIndexOnce(dir string) (*GTFSIndex, error) {
	if gtfsIndex != nil {
		return gtfsIndex, nil // already loaded
	}
	idx, err := LoadGTFS(dir)
	if err != nil {
		return nil, err
	}
	gtfsIndex = idx
	return gtfsIndex, nil
}

func GetGTFSIndex() *GTFSIndex { return gtfsIndex }

func FindClosestGTFSStop(lat, lon float64, idx *GTFSIndex) (GTFSStop, float64) {
	var best GTFSStop
	bestD := mathInf()
	user := Coordinate{Lat: lat, Lon: lon}
	for _, s := range idx.StopsByID {
		d := haversineDistance(user, Coordinate{Lat: s.Lat, Lon: s.Lon})
		if d < bestD {
			bestD = d
			best = s
		}
	}
	return best, bestD
}

func mathInf() float64 { return math.Inf(1) }

// ChooseCanonicalTripThatContainsStop picks one trip among TripsByStopID[stopID].
// Heuristic: pick the trip in the same route/direction that has the **longest stop list** (most complete pattern).
func ChooseCanonicalTripThatContainsStop(stopID string, idx *GTFSIndex) (tripID string, routeID string, direction int, err error) {
	tripIDs := idx.TripsByStopID[stopID]
	if len(tripIDs) == 0 {
		return "", "", 0, fmt.Errorf("no trips contain stop_id=%s", stopID)
	}

	var best string
	var bestLen int

	for _, tID := range tripIDs {
		stops := idx.StopTimesByTrip[tID]
		if len(stops) > bestLen {
			bestLen = len(stops)
			best = tID
		}
	}

	if best == "" {
		return "", "", 0, fmt.Errorf("no suitable trip found for stop_id=%s", stopID)
	}

	tri := idx.TripsByID[best]
	return best, tri.RouteID, tri.DirectionID, nil
}

func StopsBeforeInSameTrip(targetStopID, tripID string, idx *GTFSIndex) ([]GTFSStop, int, error) {
	seqs := idx.StopTimesByTrip[tripID]
	if len(seqs) == 0 {
		return nil, 0, fmt.Errorf("trip %s has no stop_times", tripID)
	}

	targetSeq := -1
	for _, st := range seqs {
		if st.StopID == targetStopID {
			targetSeq = st.StopSequence
			break
		}
	}
	if targetSeq < 0 {
		return nil, 0, fmt.Errorf("stop %s not in trip %s", targetStopID, tripID)
	}

	out := make([]GTFSStop, 0, len(seqs))
	for _, st := range seqs {
		if st.StopSequence < targetSeq {
			if s, ok := idx.StopsByID[st.StopID]; ok {
				out = append(out, s)
			}
		}
	}
	return out, targetSeq, nil
}
