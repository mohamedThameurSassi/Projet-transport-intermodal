package graphs_go

import (
	"container/heap"
	"fmt"
	"math"
)

func (g *Graph) AStar(startID, goalID int64) ([]int64, error) {
	heuristic := func(aID, bID int64) float64 {
		a := g.Nodes[aID]
		b := g.Nodes[bID]
		dx := (a.Longitude - b.Longitude) * math.Cos((a.Latitude+b.Latitude)/2*math.Pi/180) * 111.32
		dy := (a.Latitude - b.Latitude) * 111.32
		distanceKm := math.Sqrt(dx*dx + dy*dy)
		return distanceKm / 100.0 * 3600.0 // seconds
	}

	gScore := make(map[int64]float64)
	gScore[startID] = 0

	cameFrom := make(map[int64]int64)

	pq := &priorityQueue{}
	heap.Init(pq)
	heap.Push(pq, &pqItem{node: startID, priority: heuristic(startID, goalID)})

	closed := make(map[int64]bool)

	for pq.Len() > 0 {
		item := heap.Pop(pq).(*pqItem)
		current := item.node
		if current == goalID {
			return reconstructPath(cameFrom, current), nil
		}

		if closed[current] {
			continue
		}
		closed[current] = true
		for _, e := range g.Edges[current] {
			neighbor := e.ToID
			tentative := gScore[current] + e.TravelTime

			if old, ok := gScore[neighbor]; !ok || tentative < old {
				cameFrom[neighbor] = current
				gScore[neighbor] = tentative

				estimated := tentative + heuristic(neighbor, goalID)

				heap.Push(pq, &pqItem{node: neighbor, priority: estimated})
			}
		}
	}

	return nil, fmt.Errorf("no path found from %d to %d", startID, goalID)
}

func reconstructPath(cameFrom map[int64]int64, current int64) []int64 {
	var path []int64
	for {
		path = append([]int64{current}, path...)
		prev, ok := cameFrom[current]
		if !ok {
			break
		}
		current = prev
	}
	return path
}

type pqItem struct {
	node     int64
	priority float64
}

type priorityQueue []*pqItem

func (pq priorityQueue) Len() int           { return len(pq) }
func (pq priorityQueue) Less(i, j int) bool { return pq[i].priority < pq[j].priority }
func (pq priorityQueue) Swap(i, j int)      { pq[i], pq[j] = pq[j], pq[i] }

func (pq *priorityQueue) Push(x interface{}) {
	item := x.(*pqItem)
	*pq = append(*pq, item)
}

func (pq *priorityQueue) Pop() interface{} {
	old := *pq
	n := len(old)
	item := old[n-1]
	*pq = old[0 : n-1]
	return item
}
