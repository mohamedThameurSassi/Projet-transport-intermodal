import zipfile
import pandas as pd
import networkx as nx
import json
from networkx.readwrite import json_graph
import os
import datetime

GTFS_FOLDER = "../data/gtfs_stm-3"
OUTPUT = "../data/graphs/gtfs_graph.json"

def build_gtfs_graph():
    G = nx.MultiDiGraph()

    print("📍 Reading GTFS files...")
    stops = pd.read_csv(os.path.join(GTFS_FOLDER, "stops.txt"))
    stop_times = pd.read_csv(os.path.join(GTFS_FOLDER, "stop_times.txt"))

    print(f"🧭 Found {len(stops)} stops")

    for _, row in stops.iterrows():
        G.add_node(
            f"stop_{row['stop_id']}",
            x=row['stop_lon'],
            y=row['stop_lat'],
            mode="gtfs",
            name=row.get('stop_name', '')
        )


    print(f"🔗 Linking stops by trip_id...")
    for trip_id, group in stop_times.groupby("trip_id"):
        group = group.sort_values("stop_sequence")
        stop_ids = group["stop_id"].tolist()
        for i in range(len(stop_ids) - 1):
            G.add_edge(
                f"stop_{stop_ids[i]}", 
                f"stop_{stop_ids[i+1]}",
                mode="gtfs"
            )

    print(f"✅ Graph built with {G.number_of_nodes()} nodes and {G.number_of_edges()} edges")

    graph_data = json_graph.node_link_data(G)

    wrapped_output = {
        "metadata": {
            "generated_at": datetime.datetime.now().isoformat(),
            "source": "GTFS STM",
            "mode_info": {
                "mode": "gtfs",
                "network_type": "transit",
                "is_combined": False
            },
            "node_count": G.number_of_nodes(),
            "edge_count": G.number_of_edges()
        },
        "graph": graph_data
    }

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(wrapped_output, f, indent=2)

    print(f"📦 GTFS graph saved to {OUTPUT}")

if __name__ == "__main__":
    build_gtfs_graph()
