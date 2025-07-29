import requests
import networkx as nx
import json
from networkx.readwrite import json_graph
import datetime
import os
MONTREAL_BBOX = {
    "north": 45.72,
    "south": 45.41,
    "east": -73.47,
    "west": -73.97
}
OUTPUT_PATH = "../data/graphs/bixi_graph.json"
GBFS_URL = "https://gbfs.velobixi.com/gbfs/en/station_information.json"

def is_within_montreal(lat, lon):
    return (MONTREAL_BBOX["south"] <= lat <= MONTREAL_BBOX["north"] and
            MONTREAL_BBOX["west"] <= lon <= MONTREAL_BBOX["east"])

def build_bixi_graph():
    print("🔄 Fetching BIXI station data...")
    resp = requests.get(GBFS_URL)
    data = resp.json()

    stations = data.get("data", {}).get("stations", [])
    print(f"✅ Found {len(stations)} BIXI stations")

    if not stations:
        raise ValueError("❌ No BIXI stations found — check GBFS feed")
    filtered_stations = [s for s in stations if is_within_montreal(s['lat'], s['lon'])]
    print(f"🔍 Original stations: {len(stations)} → After filtering: {len(filtered_stations)}")
    
    G = nx.Graph()

    for station in filtered_stations:
        G.add_node(
            f"bixi_{station['station_id']}",
            x=station['lon'],
            y=station['lat'],
            mode="bixi",
            name=station['name']
        )

    graph_data = json_graph.node_link_data(G)

    wrapped_output = {
        "metadata": {
            "generated_at": datetime.datetime.now().isoformat(),
            "source": "GBFS BIXI",
            "mode_info": {
                "mode": "bixi",
                "network_type": "bixi",
                "is_combined": False
            },
            "node_count": G.number_of_nodes(),
            "edge_count": G.number_of_edges()
        },
        "graph": graph_data
    }

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(wrapped_output, f, indent=2)

    print(f"✅ BIXI graph saved to {OUTPUT_PATH}")

if __name__ == "__main__":
    build_bixi_graph()
