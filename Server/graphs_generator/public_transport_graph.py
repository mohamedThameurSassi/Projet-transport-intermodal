import zipfile
import pandas as pd
import networkx as nx
import json
from networkx.readwrite import json_graph
import os

GTFS_FOLDER = "../data/gtfs_stm-3"
OUTPUT = "../graphs/gtfs_graph.json"

def build_gtfs_graph():
    G = nx.DiGraph()

    stops = pd.read_csv(os.path.join(GTFS_FOLDER, "stops.txt"))
    stop_times = pd.read_csv(os.path.join(GTFS_FOLDER, "stop_times.txt"))
    # Add stops as nodes
    for _, row in stops.iterrows():
        G.add_node(
            f"stop_{row['stop_id']}",
            x=row['stop_lon'],
            y=row['stop_lat'],
            mode="transit"
        )

    # Add edges between stops in the same trip
    for trip_id, group in stop_times.groupby("trip_id"):
        group = group.sort_values("stop_sequence")
        stop_ids = group["stop_id"].tolist()
        for i in range(len(stop_ids) - 1):
            G.add_edge(
                f"stop_{stop_ids[i]}", 
                f"stop_{stop_ids[i+1]}",
                mode="transit"
            )

    # Save as JSON
    data = json_graph.node_link_data(G)
    with open(OUTPUT, "w") as f:
        json.dump(data, f)
    print(f"✅ Saved GTFS graph to {OUTPUT}")

if __name__ == "__main__":
    build_gtfs_graph()
