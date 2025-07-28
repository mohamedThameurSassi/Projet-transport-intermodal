import json
import networkx as nx
from scipy.spatial import KDTree
import numpy as np
from networkx.readwrite import json_graph
import os
import datetime


BIKE_PATH = "../data/graphs/bike_graph.json"
BIXI_PATH = "../data/graphs/bixi_graph.json"
OUTPUT_PATH = "../data/graphs/bike_with_bixi_graph.json"

def inject_bixi_into_bike_graph(G_bike, bixi_stations):
    G = G_bike.copy()

    bike_coords = []
    bike_ids = []
    for node, data in G.nodes(data=True):
        bike_coords.append((data['x'], data['y']))
        bike_ids.append(node)
    tree = KDTree(bike_coords)

    for station in bixi_stations:
        bixi_id = station['id']
        bixi_coord = (station['x'], station['y'])

        G.add_node(
            bixi_id,
            x=station['x'],
            y=station['y'],
            mode="bixi",
            name=station.get('name', ""),
            is_bixi=True
        )

        _, idx = tree.query(bixi_coord)
        nearest_bike_node = bike_ids[idx]

        G.add_edge(bixi_id, nearest_bike_node, mode="bixi_transfer")
        G.add_edge(nearest_bike_node, bixi_id, mode="bixi_transfer")

    return G

def load_graph_json(path):
    with open(path, "r") as f:
        data = json.load(f)
    return json_graph.node_link_graph(data["graph"] if "graph" in data else data)


def save_graph_json(graph, filename):
    metadata = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": "Montreal, Quebec, Canada",
        "mode_info": {
            "mode": "bixi",
            "is_combined": True,
            "components": ["bike", "bixi"]
        },
        "node_count": graph.number_of_nodes(),
        "edge_count": graph.number_of_edges()
    }

    output_data = {
        "metadata": metadata,
        "graph": json_graph.node_link_data(graph)
    }

    with open(filename, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"✅ Saved graph with metadata to {filename}")


def main():
    print("🚲 Loading bike graph...")
    G_bike = load_graph_json(BIKE_PATH)

    print("🔄 Loading BIXI stations...")
    with open(BIXI_PATH, "r") as f:
        bixi_data = json.load(f)
        nodes = bixi_data["graph"]["nodes"] if "graph" in bixi_data else bixi_data["nodes"]
        bixi_stations = [{"id": node["id"], "x": node["x"], "y": node["y"], "name": node.get("name", "")} for node in nodes]

    print("🔗 Injecting BIXI stations into bike graph...")
    G_combined = inject_bixi_into_bike_graph(G_bike, bixi_stations)

    save_graph_json(G_combined, OUTPUT_PATH)

if __name__ == "__main__":
    main()
