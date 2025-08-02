import zipfile
import pandas as pd
import networkx as nx
import json
from networkx.readwrite import json_graph
import os
import datetime
from datetime import datetime as dt

GTFS_FOLDER = "../data"
OUTPUT = "../data/graphs/gtfs_graph.json"

def time_to_seconds(time_str):
    """Convert HH:MM:SS time format to seconds since midnight"""
    try:
        hours, minutes, seconds = map(int, time_str.split(':'))
        # Handle times >= 24:00:00 (next day service)
        return hours * 3600 + minutes * 60 + seconds
    except:
        return 0

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
            travel_mode="transit",
            mode="transit",  # Keep legacy compatibility
            name=row.get('stop_name', ''),
            stop_id=row['stop_id']
        )


    print(f"🔗 Linking stops by trip_id and computing travel times...")
    trip_count = 0
    total_edges_added = 0
    
    for trip_id, group in stop_times.groupby("trip_id"):
        trip_count += 1
        if trip_count % 1000 == 0:
            print(f"   Processed {trip_count} trips...")
            
        group = group.sort_values("stop_sequence")
        
        # Extract stop data for this trip
        trip_data = []
        for _, row in group.iterrows():
            trip_data.append({
                'stop_id': f"stop_{row['stop_id']}",
                'arrival_time': time_to_seconds(row['arrival_time']),
                'departure_time': time_to_seconds(row['departure_time'])
            })
        
        # Create edges between consecutive stops with travel time
        for i in range(len(trip_data) - 1):
            current_stop = trip_data[i]
            next_stop = trip_data[i + 1]
            
            # Calculate travel time (arrival at next stop - departure from current stop)
            travel_time = next_stop['arrival_time'] - current_stop['departure_time']
            
            # Handle edge case where travel time is negative (crossing midnight)
            if travel_time < 0:
                travel_time += 24 * 3600  # Add 24 hours
            
            # Add edge with travel time information
            edge_data = {
                'travel_mode': 'transit',
                'travel_time': travel_time,
                'trip_id': trip_id
            }
            
            G.add_edge(
                current_stop['stop_id'], 
                next_stop['stop_id'],
                **edge_data
            )
            total_edges_added += 1

    print(f"✅ Processed {trip_count} trips, added {total_edges_added} edges with travel times")

    print(f"✅ Graph built with {G.number_of_nodes()} nodes and {G.number_of_edges()} edges")

    graph_data = json_graph.node_link_data(G)

    wrapped_output = {
        "metadata": {
            "generated_at": datetime.datetime.now().isoformat(),
            "source": "GTFS STM",
            "place": "Montreal, Quebec, Canada",
            "mode_info": {
                "mode": "transit",
                "network_type": "transit",
                "is_combined": False,
                "has_travel_times": True
            },
            "node_count": G.number_of_nodes(),
            "edge_count": G.number_of_edges(),
            "trips_processed": trip_count
        },
        "graph": graph_data
    }

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(wrapped_output, f, indent=2)

    print(f"📦 GTFS graph saved to {OUTPUT}")

if __name__ == "__main__":
    build_gtfs_graph()
