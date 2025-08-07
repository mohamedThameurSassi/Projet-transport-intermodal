# Health Route Server

A Go server that provides health-oriented route alternatives for the MultiTravel iOS app.

## Features

- Receives trip requests with origin, destination, and preferred transport type
- Returns the user's usual route plus health-oriented alternatives
- Calculates estimated calories burned, health scores, and carbon footprint
- Supports walking, biking, transit, and driving route segments

## API Endpoint

### POST /api/health-route

**Request:**
```json
{
  "origin": {
    "latitude": 45.5017,
    "longitude": -73.5673,
    "address": "Montreal, QC"
  },
  "destination": {
    "latitude": 45.5088,
    "longitude": -73.5541,
    "address": "Downtown Montreal"
  },
  "preferredTransport": "car",
  "requestTime": "2025-08-03T10:00:00Z"
}
```

**Response:**
```json
{
  "originalRoute": {
    "id": "original",
    "segments": [...],
    "totalDuration": 1200,
    "totalDistance": 5000,
    "estimatedCalories": 0,
    "healthScore": 1,
    "carbonFootprint": 1.05
  },
  "healthAlternatives": [
    {
      "id": "walking_transit",
      "segments": [...],
      "totalDuration": 1800,
      "totalDistance": 5000,
      "estimatedCalories": 50,
      "healthScore": 7,
      "carbonFootprint": 0.2
    }
  ],
  "requestId": "trip_1691043600"
}
```

## Running the Server

1. Install dependencies:
```bash
go mod tidy
```

2. Run the server:
```bash
go run main.go
```

The server will start on port 8080.

## Health Check

```bash
curl http://localhost:8080/health
```

## Current Algorithm

The server currently uses simple heuristics to generate routes:

- **Walking**: Used for distances < 5km, 5 km/h speed, 50 cal/km
- **Biking**: Used for distances < 10km, 15 km/h speed, 40 cal/km  
- **Transit**: 30 km/h average speed, includes walking to stops
- **Driving**: 50 km/h average speed, 0.21 kg CO₂/km

## Future Enhancements

- Integration with real GTFS data for Montreal (STM, ARTM, REM)
- Real-time transit information
- Bixi bike sharing integration
- Weather-based route adjustments
- User preference learning
- Real routing algorithms (instead of straight-line estimates)
