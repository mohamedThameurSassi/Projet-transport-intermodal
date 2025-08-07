package routing

import (
	"container/heap"
	"fmt"
	"log"
	"math"
)

const (
	DEFAULT_WALK_SPEED_M_S   = 1.4
	DEFAULT_CAR_SPEED_M_S    = 13.9
	DEFAULT_SUBWAY_SPEED_M_S = 8.3
	EARTH_RADIUS_KM          = 6371.0
)

type Coordinate struct {
	Lat float64
	Lon float64
}

type RouteStep struct {
	Mode        string
	FromCoord   Coordinate
	ToCoord     Coordinate
	DurationSec float64
	DistanceM   float64
	Description string
	Error       string
}

func toRadians(degrees float64) float64 {
	return degrees * math.Pi / 180
}

func haversineDistance(coord1, coord2 Coordinate) float64 {
	phi1 := toRadians(coord1.Lat)
	phi2 := toRadians(coord2.Lat)
	deltaPhi := toRadians(coord2.Lat - coord1.Lat)
	deltaLambda := toRadians(coord2.Lon - coord1.Lon)

	a := math.Sin(deltaPhi/2)*math.Sin(deltaPhi/2) +
		math.Cos(phi1)*math.Cos(phi2)*
			math.Sin(deltaLambda/2)*math.Sin(deltaLambda/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return EARTH_RADIUS_KM * c * 1000
}

func findNearestNode(coord Coordinate, graph *Graph) (int64, float64) {
	var nearestNode int64
	minDistance := math.Inf(1)

	for nodeID, node := range graph.Nodes {
		dist := haversineDistance(coord, Coordinate{
			Lat: node.Latitude,
			Lon: node.Longitude,
		})
		if dist < minDistance {
			minDistance = dist
			nearestNode = nodeID
		}
	}

	return nearestNode, minDistance
}

func findNodesWithinWalkingTime(graph *Graph, startNode int64, maxTime float64) map[int64]float64 {
	distances := make(map[int64]float64)
	visited := make(map[int64]bool)

	maxIterations := 5000
	iterations := 0

	distances[startNode] = 0

	log.Printf("Finding nodes within %.0f seconds walking from node %d", maxTime, startNode)

	for iterations < maxIterations {
		iterations++

		var current int64
		minDist := math.Inf(1)
		found := false

		for node, dist := range distances {
			if !visited[node] && dist < minDist {
				minDist = dist
				current = node
				found = true
			}
		}

		if !found || minDist > maxTime {
			log.Printf("Walking time search completed in %d iterations, found %d reachable nodes", iterations, len(distances))
			break
		}

		visited[current] = true

		if iterations%1000 == 0 {
			log.Printf("Walking search iteration %d, current node: %d, distance: %.2f", iterations, current, minDist)
		}

		for _, edge := range graph.Edges[current] {
			if !visited[edge.ToID] {
				travelTime := edge.TravelTime
				if travelTime <= 0 {
					travelTime = edge.Distance / DEFAULT_WALK_SPEED_M_S
				}

				newDist := distances[current] + travelTime
				if newDist <= maxTime {
					if existingDist, ok := distances[edge.ToID]; !ok || newDist < existingDist {
						distances[edge.ToID] = newDist
					}
				}
			}
		}
	}

	if iterations >= maxIterations {
		log.Printf("WARNING: Walking time search hit maximum iterations limit (%d)", maxIterations)
	}

	return distances
}

type PriorityQueueItem struct {
	NodeID   int64
	Priority float64
	GScore   float64
	Index    int
}

type PriorityQueue []*PriorityQueueItem

func (pq PriorityQueue) Len() int { return len(pq) }

func (pq PriorityQueue) Less(i, j int) bool {
	return pq[i].Priority < pq[j].Priority
}

func (pq PriorityQueue) Swap(i, j int) {
	pq[i], pq[j] = pq[j], pq[i]
	pq[i].Index = i
	pq[j].Index = j
}

func (pq *PriorityQueue) Push(x interface{}) {
	n := len(*pq)
	item := x.(*PriorityQueueItem)
	item.Index = n
	*pq = append(*pq, item)
}

func (pq *PriorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	old[n-1] = nil
	item.Index = -1
	*pq = old[0 : n-1]
	return item
}

func astarHeuristic(nodeID int64, targetNode int64, graph *Graph, speedMS float64) float64 {
	node1, exists1 := graph.Nodes[nodeID]
	node2, exists2 := graph.Nodes[targetNode]

	if !exists1 || !exists2 {
		return 0.0
	}

	coord1 := Coordinate{Lat: node1.Latitude, Lon: node1.Longitude}
	coord2 := Coordinate{Lat: node2.Latitude, Lon: node2.Longitude}

	distance := haversineDistance(coord1, coord2)
	return distance / speedMS
}

func findShortestPathAStar(graph *Graph, startNode, endNode int64, mode string) ([]int64, float64, float64) {
	var speedMS float64
	switch mode {
	case "car":
		speedMS = DEFAULT_CAR_SPEED_M_S
	case "walk":
		speedMS = DEFAULT_WALK_SPEED_M_S
	case "subway", "multimodal":
		speedMS = DEFAULT_WALK_SPEED_M_S
	default:
		speedMS = DEFAULT_WALK_SPEED_M_S
	}

	if _, exists := graph.Nodes[startNode]; !exists {
		log.Printf("Start node %d not found in graph", startNode)
		return nil, 0, 0
	}
	if _, exists := graph.Nodes[endNode]; !exists {
		log.Printf("End node %d not found in graph", endNode)
		return nil, 0, 0
	}

	openSet := &PriorityQueue{}
	heap.Init(openSet)

	gScore := make(map[int64]float64)
	fScore := make(map[int64]float64)
	previous := make(map[int64]int64)
	inOpenSet := make(map[int64]bool)

	gScore[startNode] = 0
	heuristic := astarHeuristic(startNode, endNode, graph, speedMS)
	fScore[startNode] = heuristic

	startItem := &PriorityQueueItem{
		NodeID:   startNode,
		Priority: heuristic,
		GScore:   0,
	}
	heap.Push(openSet, startItem)
	inOpenSet[startNode] = true

	log.Printf("Starting A* from node %d to node %d, graph has %d nodes, mode: %s", startNode, endNode, len(graph.Nodes), mode)

	iterations := 0
	maxIterations := 10000

	for openSet.Len() > 0 && iterations < maxIterations {
		iterations++

		current := heap.Pop(openSet).(*PriorityQueueItem)
		currentNode := current.NodeID
		inOpenSet[currentNode] = false

		if currentNode == endNode {
			log.Printf("A* found path to destination in %d iterations", iterations)
			break
		}

		if iterations%1000 == 0 {
			log.Printf("A* iteration %d, current node: %d, f-score: %.2f", iterations, currentNode, current.Priority)
		}

		for _, edge := range graph.Edges[currentNode] {
			neighborNode := edge.ToID

			travelTime := edge.TravelTime
			if travelTime <= 0 {
				travelTime = edge.Distance / speedMS
			}

			tentativeGScore := gScore[currentNode] + travelTime

			if existingGScore, exists := gScore[neighborNode]; !exists || tentativeGScore < existingGScore {
				previous[neighborNode] = currentNode
				gScore[neighborNode] = tentativeGScore
				heuristic := astarHeuristic(neighborNode, endNode, graph, speedMS)
				fScore[neighborNode] = tentativeGScore + heuristic

				if !inOpenSet[neighborNode] {
					neighborItem := &PriorityQueueItem{
						NodeID:   neighborNode,
						Priority: fScore[neighborNode],
						GScore:   tentativeGScore,
					}
					heap.Push(openSet, neighborItem)
					inOpenSet[neighborNode] = true
				}
			}
		}
	}

	if iterations >= maxIterations {
		log.Printf("WARNING: A* hit maximum iterations limit (%d)", maxIterations)
		return nil, 0, 0
	}

	if _, exists := gScore[endNode]; !exists {
		log.Printf("No path found from node %d to node %d", startNode, endNode)
		return nil, 0, 0
	}

	path := make([]int64, 0)
	totalDistance := 0.0
	current := endNode

	for current != startNode {
		path = append([]int64{current}, path...)
		prev, ok := previous[current]
		if !ok {
			log.Printf("ERROR: Path reconstruction failed at node %d", current)
			return nil, 0, 0
		}

		for _, edge := range graph.Edges[prev] {
			if edge.ToID == current {
				totalDistance += edge.Distance
				break
			}
		}
		current = prev
	}
	path = append([]int64{startNode}, path...)

	totalTime := gScore[endNode]
	log.Printf("A* path found: %d nodes, total distance: %.2fm, total time: %.2fs",
		len(path), totalDistance, totalTime)

	return path, totalTime, totalDistance
}

func findShortestPath(graph *Graph, startNode, endNode int64, mode string) ([]int64, float64, float64) {
	distances := make(map[int64]float64)
	previous := make(map[int64]int64)
	visited := make(map[int64]bool)

	var speedMS float64
	switch mode {
	case "car":
		speedMS = DEFAULT_CAR_SPEED_M_S
	case "walk":
		speedMS = DEFAULT_WALK_SPEED_M_S
	default:
		speedMS = DEFAULT_WALK_SPEED_M_S
	}

	maxIterations := 10000
	iterations := 0

	for nodeID := range graph.Nodes {
		distances[nodeID] = math.Inf(1)
	}
	distances[startNode] = 0

	log.Printf("Starting Dijkstra from node %d to node %d, graph has %d nodes, mode: %s", startNode, endNode, len(graph.Nodes), mode)

	for iterations < maxIterations {
		iterations++

		var current int64
		minDist := math.Inf(1)
		found := false

		for node, dist := range distances {
			if !visited[node] && dist < minDist {
				minDist = dist
				current = node
				found = true
			}
		}

		if !found || current == endNode {
			if current == endNode {
				log.Printf("Found path to destination in %d iterations", iterations)
			} else {
				log.Printf("No more unvisited nodes after %d iterations", iterations)
			}
			break
		}

		if minDist == math.Inf(1) {
			log.Printf("No path found after %d iterations", iterations)
			break
		}

		visited[current] = true

		if iterations%1000 == 0 {
			log.Printf("Dijkstra iteration %d, current node: %d, distance: %.2f", iterations, current, minDist)
		}

		for _, edge := range graph.Edges[current] {
			if !visited[edge.ToID] {
				travelTime := edge.TravelTime
				if travelTime <= 0 {
					travelTime = edge.Distance / speedMS
				}

				newDist := distances[current] + travelTime
				if newDist < distances[edge.ToID] {
					distances[edge.ToID] = newDist
					previous[edge.ToID] = current
				}
			}
		}
	}

	if iterations >= maxIterations {
		log.Printf("WARNING: Dijkstra hit maximum iterations limit (%d)", maxIterations)
		return nil, 0, 0
	}

	if distances[endNode] == math.Inf(1) {
		log.Printf("No path found from node %d to node %d", startNode, endNode)
		return nil, 0, 0
	}

	// Build path
	path := make([]int64, 0)
	totalDistance := 0.0
	current := endNode

	for current != startNode {
		path = append([]int64{current}, path...)
		prev, ok := previous[current]
		if !ok {
			log.Printf("ERROR: Path reconstruction failed at node %d", current)
			return nil, 0, 0
		}
		for _, edge := range graph.Edges[prev] {
			if edge.ToID == current {
				totalDistance += edge.Distance
				break
			}
		}
		current = prev
	}
	path = append([]int64{startNode}, path...)

	log.Printf("Path found: %d nodes, total distance: %.2fm, total time: %.2fs",
		len(path), totalDistance, distances[endNode])

	return path, distances[endNode], totalDistance
}

func PlanCarPlusLastWalk(
	startCoord Coordinate,
	endCoord Coordinate,
	walkGraph *Graph,
	carGraph *Graph,
	walkDurationMinutes float64,
) []RouteStep {
	log.Printf("=== Starting PlanCarPlusLastWalk ===")
	log.Printf("Start: (%.6f, %.6f), End: (%.6f, %.6f), Max walk: %.1f minutes",
		startCoord.Lat, startCoord.Lon, endCoord.Lat, endCoord.Lon, walkDurationMinutes)
	log.Printf("Walk graph: %d nodes, %d edge groups", len(walkGraph.Nodes), len(walkGraph.Edges))
	log.Printf("Car graph: %d nodes, %d edge groups", len(carGraph.Nodes), len(carGraph.Edges))

	steps := make([]RouteStep, 0)
	walkDurationSec := walkDurationMinutes * 60

	log.Printf("Step 1: Finding nearest nodes...")
	endWalkNode, endWalkDist := findNearestNode(endCoord, walkGraph)
	carStartNode, carStartDist := findNearestNode(startCoord, carGraph)
	log.Printf("Nearest walk node to destination: %d (%.2fm away)", endWalkNode, endWalkDist)
	log.Printf("Nearest car node to start: %d (%.2fm away)", carStartNode, carStartDist)

	log.Printf("Step 2: Finding walkable nodes within %.0f seconds...", walkDurationSec)
	walkCandidates := findNodesWithinWalkingTime(walkGraph, endWalkNode, walkDurationSec)
	log.Printf("Found %d nodes within walking distance", len(walkCandidates))

	if len(walkCandidates) == 0 {
		log.Printf("ERROR: No walkable nodes found within time limit")
		return steps
	}

	log.Printf("Step 3: Finding optimal walking start point...")
	var walkStartNode int64
	bestDistance := math.Inf(1)

	for node := range walkCandidates {
		nodeCoord := Coordinate{
			Lat: walkGraph.Nodes[node].Latitude,
			Lon: walkGraph.Nodes[node].Longitude,
		}
		dist := haversineDistance(startCoord, nodeCoord)
		if dist < bestDistance {
			bestDistance = dist
			walkStartNode = node
		}
	}
	log.Printf("Best walking start node: %d (%.2fm from origin)", walkStartNode, bestDistance)

	walkStartCoord := Coordinate{
		Lat: walkGraph.Nodes[walkStartNode].Latitude,
		Lon: walkGraph.Nodes[walkStartNode].Longitude,
	}
	log.Printf("Step 4: Finding nearest car node to walk start point...")
	carEndNode, carEndDist := findNearestNode(walkStartCoord, carGraph)
	log.Printf("Nearest car node to walk start: %d (%.2fm away)", carEndNode, carEndDist)

	log.Printf("Step 5: Calculating car route from %d to %d...", carStartNode, carEndNode)
	carPath, carTime, carDistance := findShortestPathAStar(carGraph, carStartNode, carEndNode, "car")
	if len(carPath) > 0 {
		log.Printf("Car route found: %d nodes, %.2fm, %.2fs", len(carPath), carDistance, carTime)
		steps = append(steps, RouteStep{
			Mode:        "car",
			FromCoord:   startCoord,
			ToCoord:     walkStartCoord,
			DurationSec: carTime,
			DistanceM:   carDistance,
			Description: "Drive to walking start point",
		})
	} else {
		log.Printf("WARNING: No car route found")
	}

	log.Printf("Step 6: Calculating walking route from %d to %d...", walkStartNode, endWalkNode)
	walkPath, walkTime, walkDistance := findShortestPathAStar(walkGraph, walkStartNode, endWalkNode, "walk")
	if len(walkPath) > 0 {
		log.Printf("Walk route found: %d nodes, %.2fm, %.2fs", len(walkPath), walkDistance, walkTime)
		steps = append(steps, RouteStep{
			Mode:        "walk_final",
			FromCoord:   walkStartCoord,
			ToCoord:     endCoord,
			DurationSec: walkTime,
			DistanceM:   walkDistance,
			Description: "Walk to destination",
		})
	} else {
		log.Printf("WARNING: No walking route found")
	}

	log.Printf("=== PlanCarPlusLastWalk completed with %d steps ===", len(steps))
	return steps
}

func PlanSubwayPlusWalk(
	startCoord Coordinate,
	endCoord Coordinate,
	walkSubwayGraph *Graph,
	walkDurationMinutes float64,
) []RouteStep {
	log.Printf("=== Starting PlanSubwayPlusWalk ===")
	log.Printf("Start: (%.6f, %.6f), End: (%.6f, %.6f), Max walk: %.1f minutes",
		startCoord.Lat, startCoord.Lon, endCoord.Lat, endCoord.Lon, walkDurationMinutes)
	log.Printf("Walk+Subway graph: %d nodes, %d edge groups", len(walkSubwayGraph.Nodes), len(walkSubwayGraph.Edges))

	steps := make([]RouteStep, 0)
	walkDurationSec := walkDurationMinutes * 60

	log.Printf("Step 1: Finding nearest start node...")
	startNode, startDist := findNearestNode(startCoord, walkSubwayGraph)
	log.Printf("Nearest start node: %d (%.2fm away)", startNode, startDist)

	log.Printf("Step 2: Finding nearest end node...")
	endNode, endDist := findNearestNode(endCoord, walkSubwayGraph)
	log.Printf("Nearest end node: %d (%.2fm away)", endNode, endDist)

	log.Printf("Step 3: Finding reachable nodes within %.0f seconds walking from start...", walkDurationSec)
	startReachableNodes := findNodesWithinWalkingTime(walkSubwayGraph, startNode, walkDurationSec)
	log.Printf("Found %d nodes reachable from start", len(startReachableNodes))

	log.Printf("Step 4: Finding reachable nodes within %.0f seconds walking from destination...", walkDurationSec)
	endReachableNodes := findNodesWithinWalkingTime(walkSubwayGraph, endNode, walkDurationSec)
	log.Printf("Found %d nodes reachable from destination", len(endReachableNodes))

	if len(startReachableNodes) == 0 || len(endReachableNodes) == 0 {
		log.Printf("ERROR: Insufficient reachable nodes for complete route")
		targetCoord := Coordinate{
			Lat: walkSubwayGraph.Nodes[startNode].Latitude,
			Lon: walkSubwayGraph.Nodes[startNode].Longitude,
		}
		steps = append(steps, RouteStep{
			Mode:        "walk_to_transit",
			FromCoord:   startCoord,
			ToCoord:     targetCoord,
			DurationSec: startDist / 1.4,
			DistanceM:   startDist,
			Description: "Walk to nearest subway station",
			Error:       "Limited routing data available",
		})
		return steps
	}

	log.Printf("Step 5: Finding best start station within walking distance...")
	var bestStartStation int64
	bestDistanceToDestination := math.Inf(1)
	var bestWalkToStationTime, bestWalkToStationDist float64

	for startStationID, walkTimeToStation := range startReachableNodes {
		if walkTimeToStation <= walkDurationSec {
			startStationCoord := Coordinate{
				Lat: walkSubwayGraph.Nodes[startStationID].Latitude,
				Lon: walkSubwayGraph.Nodes[startStationID].Longitude,
			}

			distanceToDestination := haversineDistance(startStationCoord, endCoord)

			if distanceToDestination < bestDistanceToDestination {
				bestDistanceToDestination = distanceToDestination
				bestStartStation = startStationID
				bestWalkToStationTime = walkTimeToStation

				_, _, walkToStationDist := findShortestPathAStar(walkSubwayGraph, startNode, startStationID, "walk")
				bestWalkToStationDist = walkToStationDist
			}
		}
	}

	if bestStartStation == 0 {
		log.Printf("ERROR: No start station found within walking time constraint")
		return steps
	}

	log.Printf("Best start station: %d (%.2fm from destination, %.2fs walk)",
		bestStartStation, bestDistanceToDestination, bestWalkToStationTime)

	log.Printf("Step 6: Finding best end station within walking distance from destination...")
	var bestEndStation int64
	bestTotalRouteTime := math.Inf(1)
	var bestWalkFromStationTime, bestWalkFromStationDist float64

	startStationCoord := Coordinate{
		Lat: walkSubwayGraph.Nodes[bestStartStation].Latitude,
		Lon: walkSubwayGraph.Nodes[bestStartStation].Longitude,
	}

	for endStationID, walkTimeFromStation := range endReachableNodes {
		if walkTimeFromStation <= walkDurationSec && endStationID != bestStartStation {
			endStationCoord := Coordinate{
				Lat: walkSubwayGraph.Nodes[endStationID].Latitude,
				Lon: walkSubwayGraph.Nodes[endStationID].Longitude,
			}

			subwayDistance := haversineDistance(startStationCoord, endStationCoord)
			subwayTime := subwayDistance / (40.0 / 3.6)

			totalRouteTime := bestWalkToStationTime + subwayTime + walkTimeFromStation

			if totalRouteTime < bestTotalRouteTime {
				bestTotalRouteTime = totalRouteTime
				bestEndStation = endStationID
				bestWalkFromStationTime = walkTimeFromStation

				_, _, walkFromStationDist := findShortestPathAStar(walkSubwayGraph, endStationID, endNode, "walk")
				bestWalkFromStationDist = walkFromStationDist
			}
		}
	}

	if bestStartStation == 0 || bestEndStation == 0 {
		log.Printf("ERROR: No valid station pair found within walking constraints")
		log.Printf("Start station: %d, End station: %d", bestStartStation, bestEndStation)
		return steps
	}

	startStationCoord = Coordinate{
		Lat: walkSubwayGraph.Nodes[bestStartStation].Latitude,
		Lon: walkSubwayGraph.Nodes[bestStartStation].Longitude,
	}
	endStationCoord := Coordinate{
		Lat: walkSubwayGraph.Nodes[bestEndStation].Latitude,
		Lon: walkSubwayGraph.Nodes[bestEndStation].Longitude,
	}

	log.Printf("Final route: Start station %d, End station %d", bestStartStation, bestEndStation)
	log.Printf("Walk to station: %.1f min (%.2fm), Walk from station: %.1f min (%.2fm)",
		bestWalkToStationTime/60, bestWalkToStationDist, bestWalkFromStationTime/60, bestWalkFromStationDist)
	log.Printf("Walking times are within %.1f minute constraint: %v, %v",
		walkDurationMinutes,
		bestWalkToStationTime <= walkDurationSec,
		bestWalkFromStationTime <= walkDurationSec)

	steps = append(steps, RouteStep{
		Mode:        "walk_to_transit",
		FromCoord:   startCoord,
		ToCoord:     startStationCoord,
		DurationSec: bestWalkToStationTime,
		DistanceM:   bestWalkToStationDist,
		Description: fmt.Sprintf("Walk to subway station (%.1f min)", bestWalkToStationTime/60),
	})

	subwayDistance := haversineDistance(startStationCoord, endStationCoord)
	subwayTime := subwayDistance / (40.0 / 3.6)

	steps = append(steps, RouteStep{
		Mode:        "transit",
		FromCoord:   startStationCoord,
		ToCoord:     endStationCoord,
		DurationSec: subwayTime,
		DistanceM:   subwayDistance,
		Description: fmt.Sprintf("Take subway (%.1f km, %.1f min)", subwayDistance/1000, subwayTime/60),
	})

	steps = append(steps, RouteStep{
		Mode:        "walk_from_transit",
		FromCoord:   endStationCoord,
		ToCoord:     endCoord,
		DurationSec: bestWalkFromStationTime,
		DistanceM:   bestWalkFromStationDist,
		Description: fmt.Sprintf("Walk to destination (%.1f min)", bestWalkFromStationTime/60),
	})

	log.Printf("=== PlanSubwayPlusWalk completed with %d steps ===", len(steps))
	log.Printf("Total walking time: %.1f min (constraint: %.1f min)",
		(bestWalkToStationTime+bestWalkFromStationTime)/60, walkDurationMinutes)
	return steps
}
