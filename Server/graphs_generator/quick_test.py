"""
Quick routing performance test with standardized graph schema.
"""

import json
import time
import networkx as nx
from networkx.readwrite import json_graph
import random

from multimodal_graph_utils import load_graph, Mode

# Preference weights (example, tunable later)
CAR_PENALTY = 30          # add 30s extra for car edges
SUBWAY_BONUS = 15         # subtract 15s (i.e., reward) for GTFS usage
WALK_REWARD = 5           # reward for walking (soft)
BIKE_HEALTH_BONUS = 10    # bonus for bike segments

def effective_edge_cost(edge_data):
    cost = edge_data.get("travel_time", 0)
    mode = edge_data.get("travel_mode", "")
    if mode == Mode.CAR.value:
        cost += CAR_PENALTY
    if mode == Mode.GTFS.value:
        cost -= SUBWAY_BONUS
    if mode == Mode.WALK.value:
        cost -= WALK_REWARD
    if mode == Mode.BIKE.value:
        cost -= BIKE_HEALTH_BONUS
    # don't let it go below a small floor
    return max(cost, 0.1)

def load_graph_wrapper(filename):
    try:
        G = load_graph(f"../data/graphs/{filename}")
        return G
    except Exception as e:
        print(f"Failed to load {filename}: {e}")
        return None

def astar_custom(G, source, target):
    return nx.astar_path(G, source, target, heuristic=lambda u,v: 0, weight=lambda u,v,data: effective_edge_cost(data))

def main():
    graph_names = [
        "car_graph.json",
        "walk_graph.json",
        "bike_graph.json",
        "gtfs_graph.json",
        "bike_with_bixi_graph.json"
    ]
    results = {}
    for name in graph_names:
        G = load_graph_wrapper(name)
        if G is None:
            continue
        nodes = list(G.nodes)
        if len(nodes) < 2:
            continue
        source, target = random.sample(nodes, 2)
        print(f"\nRouting on {name} from {source} to {target}")
        start = time.time()
        try:
            path = astar_custom(G, source, target)
            duration = time.time() - start
            results[name] = duration
            print(f"✅ Path length: {len(path)} steps, time taken: {duration:.4f}s")
            # inspect mode switches
            prev_mode = None
            for u, v in zip(path, path[1:]):
                data = G.get_edge_data(u, v)
                if data:
                    # if multiedge pick first
                    if isinstance(data, dict):
                        edge_data = list(data.values())[0] if any(isinstance(vv, dict) for vv in data.values()) else next(iter(data.values()))
                    else:
                        edge_data = data
                    mode = edge_data.get("travel_mode")
                    if mode != prev_mode:
                        print(f"🔄 TRANSFER or mode change: {u} -> {v}, mode = {mode}")
                    prev_mode = mode
        except Exception as e:
            print(f"Routing failed: {e}")

    print(f"\n{'='*60}")
    print(f"📊 FINAL RESULTS SUMMARY")
    for name, time_val in sorted(results.items(), key=lambda x: x[1]):
        print(f"   {name:<25} {time_val:.4f}s")

if __name__ == "__main__":
    main()
