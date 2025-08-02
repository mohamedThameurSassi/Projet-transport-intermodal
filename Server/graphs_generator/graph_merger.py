import os
import json
import itertools
import networkx as nx
from networkx.readwrite import json_graph
from scipy.spatial import KDTree
import numpy as np
import math
import datetime

GRAPH_DIR = "../data/graphs"
OUTPUT_DIR = "../data/graphs/combined"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Updated graph files - excluding walk as per requirements
graph_files = {
    "car": "car_graph.json",
    "bike": "bike_graph.json", 
    "bixi": "bike_with_bixi_graph.json",
    "gtfs": "gtfs_graph.json"
}

# Transfer configuration
TRANSFER_CONFIG = {
    "max_distance_km": 0.5,  # Maximum walking distance for transfers
    "walking_speed_kmh": 5.0,  # Walking speed for transfer time calculation
}

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

def add_transfer_edges(merged_graph, modes):
    """Add transfer edges between different transport modes"""
    if len(modes) < 2:
        return merged_graph
    
    print(f"🔗 Adding transfer edges between modes: {modes}")
    
    # Group nodes by mode
    nodes_by_mode = {}
    for node, data in merged_graph.nodes(data=True):
        mode = data.get('travel_mode', data.get('mode', 'unknown'))
        if mode not in nodes_by_mode:
            nodes_by_mode[mode] = []
        nodes_by_mode[mode].append((node, (data.get('x'), data.get('y'))))
    
    transfer_edges_added = 0
    
    # Define valid transfer pairs
    valid_transfers = [
        ('car', 'transit'),     # Park & Ride
        ('car', 'bixi'),        # Drive to BIXI
        ('car', 'bike'),        # Drive to bike parking
        ('bike', 'transit'),    # Bike & Ride
        ('bixi', 'transit'),    # BIXI to transit
        ('transit', 'car'),     # Transit to car (reverse)
        ('transit', 'bike'),    # Transit to bike (reverse)
        ('transit', 'bixi'),    # Transit to BIXI (reverse)
        ('bike', 'car'),        # Bike to car (reverse)
        ('bixi', 'car'),        # BIXI to car (reverse)
    ]
    
    for mode1, mode2 in valid_transfers:
        if mode1 not in nodes_by_mode or mode2 not in nodes_by_mode:
            continue
            
        if mode1 not in modes or mode2 not in modes:
            continue
        
        print(f"   Adding {mode1} ↔ {mode2} transfers...")
        
        # Build KDTree for mode2 nodes
        mode2_coords = [coord for _, coord in nodes_by_mode[mode2] if coord[0] is not None and coord[1] is not None]
        mode2_nodes = [node for node, coord in nodes_by_mode[mode2] if coord[0] is not None and coord[1] is not None]
        
        if not mode2_coords:
            continue
            
        tree = KDTree(mode2_coords)
        
        # For each mode1 node, find nearby mode2 nodes
        for node1, coord1 in nodes_by_mode[mode1]:
            if coord1[0] is None or coord1[1] is None:
                continue
                
            # Find nearest mode2 nodes
            distances, indices = tree.query(coord1, k=min(3, len(mode2_coords)))
            if np.isscalar(distances):
                distances = [distances]
                indices = [indices]
                
            for dist_euclidean, idx in zip(distances, indices):
                node2 = mode2_nodes[idx]
                coord2 = mode2_coords[idx]
                
                # Calculate actual distance
                actual_distance = calculate_distance(coord1, coord2)
                
                if actual_distance <= TRANSFER_CONFIG["max_distance_km"]:
                    # Calculate walking time for transfer
                    transfer_time = (actual_distance / TRANSFER_CONFIG["walking_speed_kmh"]) * 3600
                    
                    # Add transfer edge
                    merged_graph.add_edge(
                        node1, node2,
                        travel_mode="transfer",
                        travel_time=transfer_time,
                        distance_km=actual_distance,
                        transfer_from=mode1,
                        transfer_to=mode2
                    )
                    transfer_edges_added += 1
                    break  # Only connect to closest valid node
    
    print(f"✅ Added {transfer_edges_added} transfer edges")
    return merged_graph

def load_graph(filename):
    """Load graph from JSON file"""
    with open(os.path.join(GRAPH_DIR, filename)) as f:
        print(f"📂 Loading graph from {filename}...")
        data = json.load(f)
        if "graph" in data:
            graph_data = data["graph"]
        else:
            graph_data = data
        
        graph = json_graph.node_link_graph(graph_data)
        print(f"   Loaded {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges")
        return graph

def save_merged_graph(graph, name, modes):
    """Save merged graph with enhanced metadata"""
    path = os.path.join(OUTPUT_DIR, f"{name}_graph.json")
    
    # Count transfer edges
    transfer_edge_count = sum(1 for _, _, data in graph.edges(data=True) 
                            if data.get('travel_mode') == 'transfer')
    
    metadata = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": "Montreal, Quebec, Canada",
        "modes": modes,
        "is_combined": True,
        "node_count": graph.number_of_nodes(),
        "edge_count": graph.number_of_edges(),
        "transfer_edge_count": transfer_edge_count,
        "transfer_config": TRANSFER_CONFIG
    }
    
    data = {
        "metadata": metadata,
        "graph": json_graph.node_link_data(graph)
    }
    
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"✅ Saved combined graph: {path}")
    print(f"   📊 {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges ({transfer_edge_count} transfers)")

def is_valid_combo(combo):
    """Check if mode combination is valid according to business rules"""
    # Rule 1: bixi and bike cannot be in the same trip
    if "bike" in combo and "bixi" in combo:
        return False
    
    # Rule 2: walking is excluded (already removed from graph_files)
    
    # Rule 3: Must have at least 2 modes to be meaningful
    if len(combo) < 2:
        return False
    
    return True

def main():
    """Generate all valid mode combinations with transfer edges"""
    print("🚀 Starting multimodal graph generation...")
    print(f"📋 Available modes: {list(graph_files.keys())}")
    
    labels = list(graph_files.keys())
    combinations_generated = 0

    # Generate combinations from 2 to all modes
    for r in range(2, len(labels) + 1):
        for combo in itertools.combinations(labels, r):
            if not is_valid_combo(combo):
                print(f"⏭️  Skipping invalid combination: {combo}")
                continue
            
            print(f"\n🔧 Processing combination: {combo}")
            
            # Load individual graphs
            files = [graph_files[label] for label in combo]
            graphs = []
            
            for filename in files:
                try:
                    graph = load_graph(filename)
                    graphs.append(graph)
                except Exception as e:
                    print(f"❌ Error loading {filename}: {e}")
                    break
            else:
                # Merge graphs
                print("🔄 Merging graphs...")
                merged = nx.compose_all(graphs)
                
                # Add transfer edges between modes
                merged = add_transfer_edges(merged, list(combo))
                
                # Save combined graph
                name = "_".join(combo)
                save_merged_graph(merged, name, list(combo))
                combinations_generated += 1

    print(f"\n🎉 Generated {combinations_generated} multimodal graph combinations!")
    print(f"📁 Output directory: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
