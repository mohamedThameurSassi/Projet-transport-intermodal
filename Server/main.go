package main

import (
	"encoding/json"
	"fmt"
	"github.com/gorilla/mux"
	"log"
	"net/http"
)

type Position struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type TransportType string

const (
	Walking TransportType = "walking"
	Driving TransportType = "driving"
	Transit TransportType = "transit"
	Cycling TransportType = "cycling"
)

type RoutingRequest struct {
	StartPosition  Position        `json:"start_position"`
	EndPosition    Position        `json:"end_position"`
	TransportTypes []TransportType `json:"transport_types"`
}

type RoutingResponse struct {
	Message string         `json:"message"`
	Request RoutingRequest `json:"request"`
}

type DirectionsResponse struct {
	Message string         `json:"message"`
	Request RoutingRequest `json:"request"`
}

func directionsHandler(w http.ResponseWriter, r *http.Request) {
	var req RoutingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid request"})
		return
	}
	log.Printf("Received directions request: %+v", req)
	resp := DirectionsResponse{
		Message: "Directions calculated (placeholder)",
		Request: req,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/directions", directionsHandler).Methods("POST")
	fmt.Println("Server running on :8080")
	log.Fatal(http.ListenAndServe(":8080", r))
}
