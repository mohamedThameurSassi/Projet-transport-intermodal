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

        print(f"✅ Modified {modified_edges} edges with traffic data")
        print(f"❌ Failed to process {failed_edges} edges")
        return graph
