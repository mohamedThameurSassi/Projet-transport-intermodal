import re
import requests
import pandas as pd
import geopandas as gpd
from shapely.geometry import Point, LineString
import networkx as nx
from datetime import datetime
import numpy as np


class TrafficDataProcessor:
    def __init__(self, data_url="https://open.canada.ca/data/en/dataset/c77c495a-2a4c-447e-9184-25722289007f/resource/ad2f6f75-4250-48c3-a468-4bdf71064f11/download/nths.geojson"):
        self.data_url = data_url
        self.traffic_data = None
        self.time_profiles = {}
        self.montreal_bounds = {
            'min_lat': 45.410,
            'max_lat': 45.705,
            'min_lon': -73.855,
            'max_lon': -73.485
        }
        
        # Downtown Montreal core (highest parking costs)
        self.downtown_center = {'lat': 45.5017, 'lon': -73.5673}  # Place Ville Marie
        
        # Montreal parking data URLs (replace with actual city data when available)
        self.parking_data_urls = {
            'meters': 'https://donnees.montreal.ca/dataset/stationnement-sur-rue',  # Placeholder
            'lots': 'https://donnees.montreal.ca/dataset/stationnement-hors-rue'    # Placeholder
        }
        
        self.parking_data = None
        self.parking_density_map = None

    def download_traffic_data(self):
        try:
            print("📥 Downloading traffic data...")
            gdf = gpd.read_file(self.data_url)

            if gdf.crs != 'EPSG:4326':
                gdf = gdf.to_crs(epsg=4326)

            def extract_midpoint(geom):
                if geom.geom_type == 'LineString':
                    return geom.interpolate(0.5, normalized=True)
                elif geom.geom_type == 'Point':
                    return geom
                else:
                    return None

            gdf['geometry'] = gdf['geometry'].apply(extract_midpoint)
            gdf = gdf[gdf['geometry'].notnull()]

            montreal_mask = (
                (gdf.geometry.y >= self.montreal_bounds['min_lat']) &
                (gdf.geometry.y <= self.montreal_bounds['max_lat']) &
                (gdf.geometry.x >= self.montreal_bounds['min_lon']) &
                (gdf.geometry.x <= self.montreal_bounds['max_lon'])
            )

            self.traffic_data = gdf[montreal_mask].copy()
            print(f"✅ Found {len(self.traffic_data)} traffic measurement points in Montreal area")
            return True
        except Exception as e:
            print(f"❌ Error downloading traffic data: {e}")
            return False

    def download_parking_data(self):
        """
        Download real parking data from Montreal Open Data
        TODO: Replace with actual Montreal parking datasets
        """
        print("📥 Attempting to download Montreal parking data...")
        
        # For now, we'll use traffic data as a proxy for urban density
        # This is more realistic than arbitrary radius zones
        if self.traffic_data is not None:
            self.create_density_based_parking_costs()
            return True
        else:
            print("⚠️  No traffic data available for density analysis")
            return False

    def create_density_based_parking_costs(self):
        """
        Create parking cost map based on actual traffic density data
        """
        if self.traffic_data is None:
            return
        
        print("🗺️  Creating parking cost map from traffic density...")
        
        # Calculate traffic density for each measurement point
        traffic_points = []
        for _, row in self.traffic_data.iterrows():
            volume = self._parse_traffic_counts(row)
            road_class = row.get('ROADCLASS', 'local')
            
            # Weight by road classification (highways/arterials = commercial areas)
            class_weights = {
                'Highway': 3.0,
                'Major Arterial': 2.5, 
                'Minor Arterial': 2.0,
                'Collector': 1.5
            }
            
            weight = class_weights.get(road_class, 1.0)
            density_score = volume * weight
            
            traffic_points.append({
                'lat': row.geometry.y,
                'lon': row.geometry.x,
                'density_score': density_score,
                'road_class': road_class
            })
        
        self.parking_density_map = pd.DataFrame(traffic_points)
        
        # Normalize density scores to parking rates
        max_density = self.parking_density_map['density_score'].max()
        min_density = self.parking_density_map['density_score'].min()
        
        # Map density to parking rates (CAD/hour) - based on Montreal reality
        self.parking_density_map['parking_rate'] = (
            1.0 + (self.parking_density_map['density_score'] - min_density) / 
            (max_density - min_density) * 7.0  # $1-8/hour range
        )
        
        # Map density to search time (minutes)
        self.parking_density_map['search_time'] = (
            2.0 + (self.parking_density_map['density_score'] - min_density) / 
            (max_density - min_density) * 13.0  # 2-15 minute range
        )
        
        print(f"✅ Created parking density map with {len(self.parking_density_map)} points")
        print(f"   Rate range: ${self.parking_density_map['parking_rate'].min():.1f}-${self.parking_density_map['parking_rate'].max():.1f}/hour")

    def _parse_traffic_counts(self, row):
        props = row.get('annee_en_cours', '')
        match = re.search(r'DJMA:(\d+)', props)
        if match:
            return int(match.group(1))
        return self._get_default_volume(row)

    def _get_default_volume(self, row):
        road_class = row.get('ROADCLASS', '')
        return {
            'Highway': 50000,
            'Major Arterial': 30000,
            'Minor Arterial': 15000
        }.get(road_class, 10000)

    def process_traffic_data(self):
        if self.traffic_data is None:
            print("❌ No traffic data available. Please download first.")
            return False

        time_periods = {
            'morning_rush': {'hours': (7, 9), 'factor': 1.5},
            'midday': {'hours': (10, 15), 'factor': 1.0},
            'evening_rush': {'hours': (16, 19), 'factor': 1.6},
            'night': {'hours': (20, 6), 'factor': 0.4}
        }

        for period, info in time_periods.items():
            period_data = self.traffic_data.copy()
            period_data['volume'] = period_data.apply(lambda x: self._parse_traffic_counts(x) * info['factor'], axis=1)
            self.time_profiles[period] = period_data.set_index(
                [period_data.geometry.y, period_data.geometry.x]
            )['volume']

        return True

    def get_traffic_multiplier(self, lat, lon, current_time):
        if not self.time_profiles:
            return 1.0

        hour = current_time.hour
        if 7 <= hour <= 9:
            period = 'morning_rush'
        elif 10 <= hour <= 15:
            period = 'midday'
        elif 16 <= hour <= 19:
            period = 'evening_rush'
        else:
            period = 'night'

        profile = self.time_profiles.get(period)
        if profile is None:
            return 1.0

        points = pd.DataFrame(profile.index.tolist(), columns=['lat', 'lon'])
        distances = np.sqrt(
            ((points['lat'] - lat) * 111.32) ** 2 +
            ((points['lon'] - lon) * 111.32 * np.cos(np.radians(lat))) ** 2
        )

        if distances.min() > 2.0:
            return 1.0

        nearest_idx = distances.idxmin()
        nearest_point = points.iloc[nearest_idx]
        volume = profile[(nearest_point['lat'], nearest_point['lon'])]
        normalized_volume = volume / profile.max()
        congestion_level = 1 / (1 + np.exp(-5 * (normalized_volume - 0.5)))
        return 1.0 + (congestion_level * 2.0)

    def _parse_speed(self, speed_str):
        try:
            if isinstance(speed_str, list):
                return float(speed_str[0])
            match = re.search(r'\d+', str(speed_str))
            return float(match.group()) if match else 50.0
        except:
            return 50.0

    def apply_traffic_to_graph(self, graph, reference_time=None):
        if reference_time is None:
            reference_time = datetime.now()

        print(f"🚦 Applying traffic data for time: {reference_time}")
        modified_edges = 0
        failed_edges = 0

        for u, v, key, data in graph.edges(data=True, keys=True):
            try:
                lat = lon = None
                geometry = data.get('geometry')

                if isinstance(geometry, list) and len(geometry) >= 2:
                    mid_idx = len(geometry) // 2
                    lon, lat = geometry[mid_idx]
                elif isinstance(geometry, LineString):
                    midpoint = geometry.interpolate(0.5, normalized=True)
                    lon, lat = midpoint.x, midpoint.y

                if lat is None or lon is None:
                    u_node = graph.nodes.get(u, {})
                    v_node = graph.nodes.get(v, {})
                    if 'y' in u_node and 'x' in u_node and 'y' in v_node and 'x' in v_node:
                        lat = (u_node['y'] + v_node['y']) / 2
                        lon = (u_node['x'] + v_node['x']) / 2
                    else:
                        failed_edges += 1
                        continue

                multiplier = self.get_traffic_multiplier(lat, lon, reference_time)

                if 'length' in data:
                    speed = self._parse_speed(data.get('maxspeed', 50))
                    length_km = data['length'] / 1000
                    base_time = (length_km / speed) * 3600
                    data['travel_time'] = base_time * multiplier
                    data['traffic_multiplier'] = multiplier
                    modified_edges += 1
                else:
                    failed_edges += 1
            except Exception:
                failed_edges += 1

    def apply_zoning_travel_time_penalty(self, graph, reference_time=None):
        """
        Apply travel time penalties based on OSM zoning data and downtown distance
        This makes congested/commercial areas slower, encouraging mode switches
        """
        if reference_time is None:
            reference_time = datetime.now()

        print(f"🏙️  Applying zoning-based travel time penalties...")
        modified_edges = 0
        
        for u, v, key, data in graph.edges(data=True, keys=True):
            try:
                # Get edge location (midpoint)
                lat = lon = None
                geometry = data.get('geometry')
                
                if isinstance(geometry, list) and len(geometry) >= 2:
                    mid_idx = len(geometry) // 2
                    lon, lat = geometry[mid_idx]
                elif isinstance(geometry, LineString):
                    midpoint = geometry.interpolate(0.5, normalized=True)
                    lon, lat = midpoint.x, midpoint.y
                
                if lat is None or lon is None:
                    u_node = graph.nodes.get(u, {})
                    v_node = graph.nodes.get(v, {})
                    if 'y' in u_node and 'x' in u_node and 'y' in v_node and 'x' in v_node:
                        lat = (u_node['y'] + v_node['y']) / 2
                        lon = (u_node['x'] + v_node['x']) / 2
                    else:
                        continue
                
                # Calculate zoning penalty based on road type and downtown distance
                penalty_factor = self._calculate_zoning_penalty(data, lat, lon)
                
                # Apply penalty to existing travel time
                if 'travel_time' in data:
                    data['travel_time'] *= penalty_factor
                    data['zoning_penalty'] = penalty_factor
                    modified_edges += 1
                
            except Exception:
                continue
        
        print(f"✅ Applied zoning penalties to {modified_edges} edges")
        return graph

    def _calculate_zoning_penalty(self, edge_data, lat, lon):
        """
        Calculate travel time penalty based on OSM attributes and location
        """
        penalty = 1.0  # Base (no penalty)
        
        # 1. OSM Highway classification penalty
        highway_type = edge_data.get('highway', 'residential')
        highway_penalties = {
            'motorway': 1.0,        # Highways are efficient
            'trunk': 1.1,           # Major roads, slight congestion
            'primary': 1.2,         # Primary roads, more congestion
            'secondary': 1.3,       # Secondary roads in commercial areas
            'tertiary': 1.4,        # Local commercial streets
            'residential': 1.1,     # Residential, usually less congested
            'service': 1.2,         # Service roads
            'unclassified': 1.3     # Unknown, assume moderate congestion
        }
        
        if isinstance(highway_type, list):
            highway_type = highway_type[0]
        
        penalty *= highway_penalties.get(highway_type, 1.2)
        
        # 2. Distance to downtown penalty (closer = more congested)
        downtown_distance = self.calculate_distance_km(
            lat, lon, 
            self.downtown_center['lat'], 
            self.downtown_center['lon']
        )
        
        if downtown_distance <= 2.0:           # Downtown core
            penalty *= 1.8
        elif downtown_distance <= 5.0:        # Downtown extended
            penalty *= 1.5
        elif downtown_distance <= 10.0:       # Urban area
            penalty *= 1.2
        # Suburban areas: no additional penalty
        
        # 3. OSM amenity/landuse attributes (if available)
        for key in ['amenity', 'landuse', 'shop', 'tourism']:
            if key in edge_data:
                value = edge_data[key]
                if isinstance(value, list):
                    value = value[0] if value else ''
                
                # Commercial/busy areas get higher penalties
                commercial_indicators = [
                    'commercial', 'retail', 'shop', 'restaurant', 
                    'hospital', 'school', 'university', 'mall'
                ]
                
                if any(indicator in str(value).lower() for indicator in commercial_indicators):
                    penalty *= 1.3
                    break
        
        # 4. Traffic density from our traffic data (if available)
        if self.time_profiles:
            traffic_multiplier = self.get_traffic_multiplier(lat, lon, datetime.now())
            # Convert traffic multiplier to additional penalty
            traffic_penalty = 1.0 + (traffic_multiplier - 1.0) * 0.5  # Moderate the traffic effect
            penalty *= traffic_penalty
        
        # Cap the maximum penalty to avoid unrealistic slowdowns
        return min(penalty, 3.0)  # Max 3x slower

    def calculate_distance_km(self, lat1, lon1, lat2, lon2):
        """Calculate distance in km using simple approximation"""
        lat_diff = (lat2 - lat1) * 111.32  # 1 degree lat ≈ 111.32 km
        lon_diff = (lon2 - lon1) * 111.32 * np.cos(np.radians((lat1 + lat2) / 2))
        return np.sqrt(lat_diff**2 + lon_diff**2)

    def get_parking_cost_info(self, lat, lon, duration_hours=2.0, time_of_day='business'):
        """
        Calculate parking cost based on real traffic density data
        """
        if self.parking_density_map is None:
            # Fallback to simple distance-based calculation
            return self._get_fallback_parking_cost(lat, lon, duration_hours, time_of_day)
        
        # Find nearest traffic measurement points
        distances = np.sqrt(
            ((self.parking_density_map['lat'] - lat) * 111.32) ** 2 +
            ((self.parking_density_map['lon'] - lon) * 111.32 * np.cos(np.radians(lat))) ** 2
        )
        
        # Use weighted average of 3 nearest points
        nearest_indices = distances.nsmallest(3).index
        weights = 1.0 / (distances[nearest_indices] + 0.1)  # Inverse distance weighting
        weights = weights / weights.sum()
        
        # Calculate weighted parking metrics
        avg_rate = (self.parking_density_map.loc[nearest_indices, 'parking_rate'] * weights).sum()
        avg_search_time = (self.parking_density_map.loc[nearest_indices, 'search_time'] * weights).sum()
        
        # Apply time-of-day multipliers
        time_multipliers = {
            'business': 1.0,
            'evening': 0.7,
            'weekend': 0.8
        }
        time_factor = time_multipliers.get(time_of_day, 1.0)
        
        final_rate = avg_rate * time_factor
        final_search_time = avg_search_time * time_factor
        
        # Determine zone based on actual rate
        if final_rate >= 6.0:
            zone = 'downtown_core'
        elif final_rate >= 4.0:
            zone = 'downtown_extended'
        elif final_rate >= 2.5:
            zone = 'urban_dense'
        else:
            zone = 'suburban'
        
        return {
            'zone': zone,
            'hourly_rate': round(final_rate, 2),
            'total_cost': round(final_rate * duration_hours, 2),
            'search_time_minutes': round(final_search_time, 1),
            'distance_to_downtown_km': round(self.calculate_distance_km(
                lat, lon, self.downtown_center['lat'], self.downtown_center['lon']
            ), 2),
            'data_source': 'traffic_density'
        }

    def _get_fallback_parking_cost(self, lat, lon, duration_hours, time_of_day):
        """Fallback method using distance to downtown"""
        distance = self.calculate_distance_km(
            lat, lon, self.downtown_center['lat'], self.downtown_center['lon']
        )
        
        # Simple distance-based rates
        if distance <= 2.0:
            rate, search_time, zone = 8.0, 15.0, 'downtown_core'
        elif distance <= 4.0:
            rate, search_time, zone = 5.0, 10.0, 'downtown_extended'
        elif distance <= 8.0:
            rate, search_time, zone = 3.0, 8.0, 'urban_dense'
        else:
            rate, search_time, zone = 1.0, 3.0, 'suburban'
        
        time_factor = {'business': 1.0, 'evening': 0.7, 'weekend': 0.8}.get(time_of_day, 1.0)
        
        return {
            'zone': zone,
            'hourly_rate': round(rate * time_factor, 2),
            'total_cost': round(rate * time_factor * duration_hours, 2),
            'search_time_minutes': round(search_time * time_factor, 1),
            'distance_to_downtown_km': round(distance, 2),
            'data_source': 'distance_fallback'
        }

    def add_parking_costs_to_graph(self, graph, default_duration_hours=2.0):
        """
        Add parking cost information to car graph nodes
        """
        print(f"🅿️  Adding parking cost data to graph nodes...")
        
        nodes_processed = 0
        
        for node, data in graph.nodes(data=True):
            try:
                lat = data.get('y')
                lon = data.get('x')
                
                if lat is not None and lon is not None:
                    parking_info = self.get_parking_cost_info(lat, lon, default_duration_hours)
                    
                    # Add parking data to node
                    data.update({
                        'parking_hourly_rate': parking_info['hourly_rate'],
                        'parking_total_cost': parking_info['total_cost'],
                        'parking_search_time': parking_info['search_time_minutes'],
                        'parking_zone': parking_info['zone'],
                        'distance_to_downtown': parking_info['distance_to_downtown_km']
                    })
                    
                    nodes_processed += 1
                    
            except Exception as e:
                # Skip nodes with issues
                continue
        
        print(f"✅ Added parking data to {nodes_processed} nodes")
        return graph
