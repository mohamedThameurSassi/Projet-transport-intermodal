import requests
import networkx as nx
import json
from networkx.readwrite import json_graph
import datetime
import os

# Montreal bounding box for filtering stations
MONTREAL_BBOX = {
    "north": 45.72,
    "south": 45.41,
    "east": -73.47,
    "west": -73.97
}

OUTPUT_PATH = "../data/graphs/bixi_graph.json"
GBFS_URL = "https://gbfs.velobixi.com/gbfs/en/station_information.json"

def is_within_montreal(lat, lon):
    """Check if coordinates are within Montreal bounds"""
    return (MONTREAL_BBOX["south"] <= lat <= MONTREAL_BBOX["north"] and
            MONTREAL_BBOX["west"] <= lon <= MONTREAL_BBOX["east"])

def build_bixi_graph():
    print("🔄 Fetching BIXI station data...")
    try:
        resp = requests.get(GBFS_URL, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching BIXI data: {e}")
        return

    stations = data.get("data", {}).get("stations", [])
    print(f"✅ Found {len(stations)} BIXI stations from GBFS feed")

    if not stations:
        raise ValueError("❌ No BIXI stations found — check GBFS feed")
    
    # Filter stations within Montreal bounds
    filtered_stations = [s for s in stations if is_within_montreal(s['lat'], s['lon'])]
    print(f"🔍 Filtered to {len(filtered_stations)} stations within Montreal bounds")
    
    # Create graph (undirected since BIXI stations are pickup/dropoff points)
    G = nx.Graph()

    # Add BIXI stations as nodes
    for station in filtered_stations:
        G.add_node(
            f"bixi_{station['station_id']}",
            x=station['lon'],
            y=station['lat'],
            travel_mode="bixi",
            mode="bixi",  # Keep legacy compatibility
            name=station['name'],
            station_id=station['station_id'],
            capacity=station.get('capacity', 0)
        )

    print(f"✅ Graph built with {G.number_of_nodes()} BIXI stations (nodes only - edges added by bike_to_bixi.py)")

    # Convert to JSON format
    graph_data = json_graph.node_link_data(G)

    # Prepare output with enhanced metadata
    wrapped_output = {
        "metadata": {
            "generated_at": datetime.datetime.now().isoformat(),
            "source": "GBFS BIXI Montreal",
            "place": "Montreal, Quebec, Canada", 
            "mode_info": {
                "mode": "bixi",
                "network_type": "bixi_stations",
                "is_combined": False,
                "has_travel_times": False,
                "note": "Only stations (nodes) - edges added by bike_to_bixi.py"
            },
            "node_count": G.number_of_nodes(),
            "edge_count": G.number_of_edges(),
            "total_stations_from_feed": len(stations),
            "filtered_stations": len(filtered_stations)
        },
        "graph": graph_data
    }

    # Save to file
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(wrapped_output, f, indent=2)

    print(f"✅ BIXI graph saved to {OUTPUT_PATH}")
    print(f"💡 Note: Use bike_to_bixi.py to connect BIXI stations to bike network")

if __name__ == "__main__":
    build_bixi_graph()
