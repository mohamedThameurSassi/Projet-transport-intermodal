import os
import osmnx as ox
import networkx as nx
from networkx.readwrite import json_graph
import json
import datetime
from traffic_data import TrafficDataProcessor

# -------------------- CONFIG --------------------
PLACE_NAME = "Montreal, Quebec, Canada"
OUTPUT_DIR = "../data/graphs"
MODES = {
    "car": "drive",
    "bike": "bike",
    "walk": "walk"
}
# ------------------------------------------------

def ensure_dir(path):
    if not os.path.exists(path):
        os.makedirs(path)

def save_graph_json(graph, filename, mode_info=None):
    data = json_graph.node_link_data(graph)
    for link in data["links"]:
        if "geometry" in link and hasattr(link["geometry"], "coords"):
            link["geometry"] = list(link["geometry"].coords)

    metadata = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": PLACE_NAME,
        "mode_info": mode_info or {},
        "node_count": graph.number_of_nodes(),
        "edge_count": graph.number_of_edges()
    }
    
    output_data = {
        "metadata": metadata,
        "graph": data
    }
    
    with open(filename, "w") as f:
        json.dump(output_data, f, indent=2)
    print(f"✅ Saved: {filename} ({metadata['node_count']} nodes, {metadata['edge_count']} edges)")

    with open(f"{OUTPUT_DIR}/car_graph.json") as f:
        car_graph_data = json.load(f)
        sample_links = car_graph_data['graph']['links'][:5]
        for i, link in enumerate(sample_links):
            print(f"Link {i}: travel_time = {link.get('travel_time')}, multiplier = {link.get('traffic_multiplier')}")


def create_individual_graphs_index():
    """Create index file for individual mode graphs only"""
    import datetime
    
    graph_files = []
    
    for mode in MODES.keys():
        graph_files.append({
            "filename": f"{mode}_graph.json",
            "type": "single_mode",
            "modes": [mode],
            "description": f"Individual graph for {mode} transportation",
            "network_type": MODES[mode]
        })
    
    index_data = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": PLACE_NAME,
        "available_graphs": graph_files,
        "total_graphs": len(graph_files),
        "note": "Individual mode graphs only. Use graph_merger.py for multimodal combinations."
    }
    
    index_path = f"{OUTPUT_DIR}/individual_graphs_index.json"
    with open(index_path, "w") as f:
        json.dump(index_data, f, indent=2)
    print(f"📋 Created individual graphs index: {index_path}")

def main():
    ox.settings.log_console = True
    ox.settings.use_cache = True

    ensure_dir(OUTPUT_DIR)

    # Initialize traffic processor
    traffic_processor = TrafficDataProcessor()
    print("Downloading and processing traffic data...")
    if traffic_processor.download_traffic_data():
        traffic_processor.process_traffic_data()
        # Create parking cost map from real traffic density data
        traffic_processor.download_parking_data()

    # Generate individual mode graphs only
    for mode, net_type in MODES.items():
        print(f"\n📥 Downloading '{mode}' graph...")
        graph = ox.graph_from_place(PLACE_NAME, network_type=net_type)
        
        # Apply mode-specific enhancements
        if mode == "car":
            print("🚗 Applying traffic data to car network...")
            graph = traffic_processor.apply_traffic_to_graph(graph)
            print("🅿️  Adding parking cost data to car network...")
            graph = traffic_processor.add_parking_costs_to_graph(graph)
            print("🏙️  Applying zoning-based travel time penalties...")
            graph = traffic_processor.apply_zoning_travel_time_penalty(graph)
        
        mode_info = {
            "mode": mode,
            "network_type": net_type,
            "is_combined": False,
            "has_traffic_data": mode == "car",
            "has_parking_data": mode == "car"
        }
        save_graph_json(graph, f"{OUTPUT_DIR}/{mode}_graph.json", mode_info)

    create_individual_graphs_index()
    print("\n🎉 Individual mode graphs generated successfully!")
    print("💡 Use graph_merger.py to create multimodal combinations")

if __name__ == "__main__":
    main()
