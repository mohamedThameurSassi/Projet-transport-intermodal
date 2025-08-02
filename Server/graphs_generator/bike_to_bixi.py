import json
import networkx as nx
from scipy.spatial import KDTree
import numpy as np
from networkx.readwrite import json_graph
import os
import datetime
import math

BIKE_PATH = "../data/graphs/bike_graph.json"
BIXI_PATH = "../data/graphs/bixi_graph.json"
OUTPUT_PATH = "../data/graphs/bike_with_bixi_graph.json"

# Walking speed for transfers (km/h)
WALKING_SPEED_KMH = 5.0

def calculate_distance(coord1, coord2):
    """Calculate distance between two coordinates using Haversine formula"""
    lat1, lon1 = coord1[1], coord1[0]  # coord format is (x, y) = (lon, lat)
    lat2, lon2 = coord2[1], coord2[0]
    
    # Convert to radians
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    
    # Haversine formula
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    
    # Earth's radius in kilometers
    r = 6371
    return r * c

def inject_bixi_into_bike_graph(G_bike, bixi_stations, max_transfer_distance_km=0.5):
    """Inject BIXI stations into bike graph with walking transfer edges"""
    G = G_bike.copy()

    # Build KDTree for efficient nearest neighbor search
    bike_coords = []
    bike_ids = []
    for node, data in G.nodes(data=True):
        bike_coords.append((data['x'], data['y']))
        bike_ids.append(node)
    tree = KDTree(bike_coords)

    transfer_edges_added = 0
    stations_added = 0

    for station in bixi_stations:
        bixi_id = station['id']
        bixi_coord = (station['x'], station['y'])

        # Add BIXI station node
        G.add_node(
            bixi_id,
            x=station['x'],
            y=station['y'],
            travel_mode="bixi",
            mode="bixi",
            name=station.get('name', ""),
            is_bixi=True
        )
        stations_added += 1

        # Find nearest bike network nodes within transfer distance
        distances, indices = tree.query(bixi_coord, k=5)  # Check top 5 nearest
        
        for dist, idx in zip(distances, indices):
            nearest_bike_node = bike_ids[idx]
            bike_coord = bike_coords[idx]
            
            # Calculate actual distance in km
            actual_distance = calculate_distance(bixi_coord, bike_coord)
            
            if actual_distance <= max_transfer_distance_km:
                # Calculate walking time for transfer (in seconds)
                transfer_time = (actual_distance / WALKING_SPEED_KMH) * 3600
                
                # Add bidirectional transfer edges
                G.add_edge(bixi_id, nearest_bike_node, 
                          travel_mode="bixi_transfer",
                          travel_time=transfer_time,
                          distance_km=actual_distance)
                G.add_edge(nearest_bike_node, bixi_id, 
                          travel_mode="bixi_transfer", 
                          travel_time=transfer_time,
                          distance_km=actual_distance)
                transfer_edges_added += 2
                break  # Only connect to closest valid node

    print(f"✅ Added {stations_added} BIXI stations and {transfer_edges_added} transfer edges")
    return G

def load_graph_json(path):
    with open(path, "r") as f:
        data = json.load(f)
    return json_graph.node_link_graph(data["graph"] if "graph" in data else data)


def save_graph_json(graph, filename):
    """Save graph with enhanced metadata"""
    metadata = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": "Montreal, Quebec, Canada",
        "mode_info": {
            "mode": "bike_bixi",
            "network_type": "bike_with_bixi_stations",
            "is_combined": True,
            "components": ["bike", "bixi"],
            "has_travel_times": True,
            "transfer_method": "walking"
        },
        "node_count": graph.number_of_nodes(),
        "edge_count": graph.number_of_edges(),
        "walking_speed_kmh": WALKING_SPEED_KMH
    }

    output_data = {
        "metadata": metadata,
        "graph": json_graph.node_link_data(graph)
    }

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"✅ Saved bike+BIXI graph with metadata to {filename}")


def main():
    print("🚲 Loading bike graph...")
    G_bike = load_graph_json(BIKE_PATH)
    print(f"   Loaded {G_bike.number_of_nodes()} bike nodes, {G_bike.number_of_edges()} edges")

    print("🔄 Loading BIXI stations...")
    with open(BIXI_PATH, "r") as f:
        bixi_data = json.load(f)
        nodes = bixi_data["graph"]["nodes"] if "graph" in bixi_data else bixi_data["nodes"]
        bixi_stations = [{"id": node["id"], "x": node["x"], "y": node["y"], "name": node.get("name", "")} for node in nodes]
    print(f"   Found {len(bixi_stations)} BIXI stations")

    print("🔗 Injecting BIXI stations into bike graph...")
    G_combined = inject_bixi_into_bike_graph(G_bike, bixi_stations)

    save_graph_json(G_combined, OUTPUT_PATH)
    print(f"📊 Final graph: {G_combined.number_of_nodes()} nodes, {G_combined.number_of_edges()} edges")


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
