"""
Focused performance tests for specific multimodal routing scenarios
Tests the exact combinations you requested
"""

import json
import time
import networkx as nx
from networkx.readwrite import json_graph
import math
import random
from pathlib import Path

class FocusedRoutingTests:
    def __init__(self, graphs_dir="../data/graphs"):
        self.graphs_dir = Path(graphs_dir)
    
    def load_graph(self, filename):
        """Load a graph from JSON file"""
        filepath = self.graphs_dir / filename
        if not filepath.exists():
            print(f"❌ Graph file not found: {filepath}")
            return None
            
        with open(filepath, 'r') as f:
            data = json.load(f)
        
        if "graph" in data:
            graph_data = data["graph"]
        else:
            graph_data = data
            
        return json_graph.node_link_graph(graph_data)
    
    def haversine_distance(self, lat1, lon1, lat2, lon2):
        """Calculate distance between two points"""
        R = 6371000  # Earth's radius in meters
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a))
        return R * c
    
    def multimodal_astar_weight(self, G, u, v, d):
        """Weight function with transfer penalties"""
        base_cost = d.get('travel_time', d.get('length', 100) / 5 * 3.6)  # Fallback to length-based
        
        # Add transfer penalty
        if d.get('is_transfer', False):
            base_cost += 300  # 5-minute penalty
            
        return base_cost
    
    def find_random_node_pair(self, graph, min_distance_km=2, max_distance_km=8):
        """Find a random pair of nodes with reasonable distance"""
        nodes = list(graph.nodes(data=True))
        attempts = 0
        max_attempts = 1000
        
        while attempts < max_attempts:
            attempts += 1
            node1_id, node1_data = random.choice(nodes)
            node2_id, node2_data = random.choice(nodes)
            
            if node1_id == node2_id:
                continue
                
            lat1, lon1 = node1_data.get('y'), node1_data.get('x')
            lat2, lon2 = node2_data.get('y'), node2_data.get('x')
            
            if not all([lat1, lon1, lat2, lon2]):
                continue
                
            distance_km = self.haversine_distance(lat1, lon1, lat2, lon2) / 1000
            
            if min_distance_km <= distance_km <= max_distance_km:
                return node1_id, node2_id, distance_km
        
        # Fallback: just return any two nodes with coordinates
        for node1_id, node1_data in nodes:
            for node2_id, node2_data in nodes:
                if node1_id != node2_id:
                    lat1, lon1 = node1_data.get('y'), node1_data.get('x')
                    lat2, lon2 = node2_data.get('y'), node2_data.get('x')
                    if all([lat1, lon1, lat2, lon2]):
                        distance_km = self.haversine_distance(lat1, lon1, lat2, lon2) / 1000
                        return node1_id, node2_id, distance_km
        
        return None, None, 0
    
    def test_single_routing(self, graph_name, graph, num_tests=3):
        """Test routing on a single graph"""
        print(f"\n🧪 Testing {graph_name}")
        print(f"   Graph size: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges")
        
        times = []
        
        for i in range(num_tests):
            start_node, end_node, distance_km = self.find_random_node_pair(graph)
            
            if not start_node:
                print(f"   ❌ Test {i+1}: Could not find suitable node pair")
                continue
            
            print(f"   Test {i+1}: {start_node} → {end_node} ({distance_km:.2f}km)")
            
            try:
                # Measure routing time
                start_time = time.time()
                
                path = nx.astar_path(
                    graph,
                    start_node,
                    end_node,
                    weight=lambda u, v, d: self.multimodal_astar_weight(graph, u, v, d)
                )
                
                routing_time = time.time() - start_time
                times.append(routing_time)
                
                print(f"      ✅ Found path: {len(path)} nodes in {routing_time:.4f}s")
                
            except nx.NetworkXNoPath:
                print(f"      ❌ No path found")
            except Exception as e:
                print(f"      ❌ Error: {e}")
        
        if times:
            avg_time = sum(times) / len(times)
            min_time = min(times)
            max_time = max(times)
            print(f"   📊 Average: {avg_time:.4f}s | Range: {min_time:.4f}s - {max_time:.4f}s")
            return avg_time
        else:
            print(f"   📊 No successful routes")
            return None
    
    def run_focused_tests(self):
        """Run the specific tests you requested"""
        print("🎯 Running focused multimodal routing performance tests")
        print("=" * 60)
        
        test_cases = [
            # Single mode tests
            ("walk_graph.json", "Walking Only"),
            ("bike_graph.json", "Bike Only"), 
            ("car_graph.json", "Car Only"),
            ("gtfs_graph.json", "GTFS Transit Only"),
            
            # Multimodal combinations you requested
            ("combined/walk_bike_graph.json", "Walk + Bike"),
            ("combined/car_walk_graph.json", "Car + Walk"),
            ("combined/walk_gtfs_graph.json", "Walk + GTFS"),
            ("combined/car_gtfs_graph.json", "Car + GTFS"),
            
            # Comprehensive test
            ("combined/comprehensive_multimodal_graph.json", "All Modes Combined"),
        ]
        
        results = {}
        
        for filename, display_name in test_cases:
            graph = self.load_graph(filename)
            if graph is None:
                print(f"⏭️ Skipping {display_name} - file not found")
                continue
            
            avg_time = self.test_single_routing(display_name, graph, num_tests=3)
            if avg_time is not None:
                results[display_name] = avg_time
        
        # Summary
        if results:
            print("\n" + "=" * 60)
            print("📊 PERFORMANCE SUMMARY")
            print("=" * 60)
            
            sorted_results = sorted(results.items(), key=lambda x: x[1])
            
            for name, time_val in sorted_results:
                print(f"{name:<30} {time_val:.4f}s")
            
            print(f"\n🏆 Fastest: {sorted_results[0][0]} ({sorted_results[0][1]:.4f}s)")
            print(f"🐌 Slowest: {sorted_results[-1][0]} ({sorted_results[-1][1]:.4f}s)")
            
            # Speed improvement analysis
            if len(sorted_results) > 1:
                fastest_time = sorted_results[0][1]
                slowest_time = sorted_results[-1][1]
                speedup = slowest_time / fastest_time
                print(f"📈 Speed difference: {speedup:.1f}x faster")
        
        else:
            print("❌ No successful tests completed")


def main():
    """Run focused tests"""
    tester = FocusedRoutingTests()
    tester.run_focused_tests()


if __name__ == "__main__":
    main()
