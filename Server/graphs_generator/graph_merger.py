import os
import json
import itertools
import networkx as nx
from networkx.readwrite import json_graph

GRAPH_DIR = "../data/graphs"
OUTPUT_DIR = "../data/graphs/combined"
os.makedirs(OUTPUT_DIR, exist_ok=True)

graph_files = {
    "car": "car_graph.json",
    "walk": "walk_graph.json",
    "bike": "bike_graph.json",
    "bixi": "bike_with_bixi_graph.json",
    "gtfs": "gtfs_graph.json"
}

def load_graph(filename):
    with open(os.path.join(GRAPH_DIR, filename)) as f:
        print(f"Loading graph from {filename}...")
        data = json.load(f)
        if "graph" in data:
            data = data["graph"]
        return json_graph.node_link_graph(data)

def save_merged_graph(graph, name, modes):
    path = os.path.join(OUTPUT_DIR, f"{name}_graph.json")
    metadata = {
        "modes": modes,
        "node_count": graph.number_of_nodes(),
        "edge_count": graph.number_of_edges(),
    }
    data = {
        "metadata": metadata,
        "graph": json_graph.node_link_data(graph)
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"✅ Saved: {path}")

def is_valid_combo(combo):
    return not ("bike" in combo and "bixi" in combo)

def main():
    labels = list(graph_files.keys())

    for r in range(2, len(labels) + 1):
        for combo in itertools.combinations(labels, r):
            if not is_valid_combo(combo):
                continue
            files = [graph_files[label] for label in combo]
            graphs = [load_graph(f) for f in files]
            merged = nx.compose_all(graphs)
            name = "_".join(combo)
            save_merged_graph(merged, name, list(combo))

if __name__ == "__main__":
    main()
