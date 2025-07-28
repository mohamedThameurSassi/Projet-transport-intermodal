import os
import osmnx as ox
import networkx as nx
from networkx.readwrite import json_graph
import json
import datetime
from itertools import combinations

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
        if "geometry" in link:
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

def create_index_file():
    import datetime
    
    graph_files = []
    
    for mode in MODES.keys():
        graph_files.append({
            "filename": f"{mode}_graph.json",
            "type": "single_mode",
            "modes": [mode],
            "description": f"Graph for {mode} transportation"
        })
    
    # Combinations
    for combo in combinations(MODES.keys(), 2):
        mode_name = "_".join(combo)
        graph_files.append({
            "filename": f"{mode_name}_graph.json",
            "type": "multi_mode",
            "modes": list(combo),
            "description": f"Combined graph for {' and '.join(combo)} transportation"
        })
    
    # All modes
    graph_files.append({
        "filename": "car_bike_walk_graph.json",
        "type": "all_modes",
        "modes": list(MODES.keys()),
        "description": "Combined graph for all transportation modes"
    })
    
    index_data = {
        "generated_at": datetime.datetime.now().isoformat(),
        "place": PLACE_NAME,
        "available_graphs": graph_files,
        "total_graphs": len(graph_files)
    }
    
    index_path = f"{OUTPUT_DIR}/graphs_index.json"
    with open(index_path, "w") as f:
        json.dump(index_data, f, indent=2)
    print(f"📋 Created index file: {index_path}")

def main():
    ox.settings.log_console = True
    ox.settings.use_cache = True

    ensure_dir(OUTPUT_DIR)

    graphs = {}

    for mode, net_type in MODES.items():
        print(f"📥 Downloading '{mode}' graph...")
        graph = ox.graph_from_place(PLACE_NAME, network_type=net_type)
        graphs[mode] = graph
        
        mode_info = {
            "mode": mode,
            "network_type": net_type,
            "is_combined": False
        }
        save_graph_json(graph, f"{OUTPUT_DIR}/{mode}_graph.json", mode_info)

    for combo in combinations(MODES.keys(), 2):
        mode_name = "_".join(combo)
        print(f"🔗 Combining: {combo[0]} + {combo[1]}")
        G_combo = nx.compose(graphs[combo[0]], graphs[combo[1]])
        
        combo_info = {
            "modes": list(combo),
            "network_types": [MODES[mode] for mode in combo],
            "is_combined": True
        }
        save_graph_json(G_combo, f"{OUTPUT_DIR}/{mode_name}_graph.json", combo_info)

    print("🌐 Combining all modes: car + bike + walk")
    G_all = nx.compose_all([graphs[m] for m in MODES])
    
    all_info = {
        "modes": list(MODES.keys()),
        "network_types": list(MODES.values()),
        "is_combined": True
    }
    save_graph_json(G_all, f"{OUTPUT_DIR}/car_bike_walk_graph.json", all_info)
    
    create_index_file()

if __name__ == "__main__":
    main()
