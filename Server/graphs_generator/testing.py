import networkx as nx
import matplotlib.pyplot as plt
from networkx.readwrite import json_graph
import json

with open("../data/graphs/car_walk_graph.json") as f:
    data = json.load(f)
G = json_graph.node_link_graph(data["graph"])

# Plot
pos = {n: (d["x"], d["y"]) for n, d in G.nodes(data=True) if "x" in d and "y" in d}
plt.figure(figsize=(12, 12))
nx.draw(G, pos, node_size=10, edge_color="gray", alpha=0.5)
plt.title("car + walk + bixi network")
plt.show()
