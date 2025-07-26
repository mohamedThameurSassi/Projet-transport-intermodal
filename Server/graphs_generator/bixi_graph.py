import requests
import networkx as nx
import json
from networkx.readwrite import json_graph

BIXI_URL = "https://gbfs.velobixi.com/gbfs/en/station_information.json"
OUTPUT = "../graphs/bixi_graph.json"

def build_bixi_graph():
    G = nx.Graph()
    data = requests.get(BIXI_URL).json()
    stations = data["data"]["stations"]

    for station in stations:
        station_id = f"bixi_{station['station_id']}"
        G.add_node(
            station_id,
            x=station['lon'],
            y=station['lat'],
            mode="bixi",
            name=station['name']
        )


    data = json_graph.node_link_data(G)
    with open(OUTPUT, "w") as f:
        json.dump(data, f)
    print(f"✅ Saved BIXI graph to {OUTPUT}")

if __name__ == "__main__":
    build_bixi_graph()
