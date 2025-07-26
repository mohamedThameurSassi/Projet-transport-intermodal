package handlers

import (
	"encoding/json"
	"github.com/mohamedthameursassi/GoServer/models"
	"github.com/mohamedthameursassi/GoServer/services"
	"net/http"

	"github.com/gorilla/mux"
)

type RoutingHandler struct {
	routingService *services.RoutingService
}

func NewRoutingHandler(routingService *services.RoutingService) *RoutingHandler {
	return &RoutingHandler{
		routingService: routingService,
	}
}

func (h *RoutingHandler) RegisterRoutes(router *mux.Router) {
	router.HandleFunc("/api/routes", h.CalculateRoutes).Methods("POST")
	router.HandleFunc("/api/routes/modes", h.GetAvailableModes).Methods("GET")
}

func (h *RoutingHandler) CalculateRoutes(w http.ResponseWriter, r *http.Request) {
	var req models.RouteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	routes, err := h.routingService.CalculateRoutes(r.Context(), req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"routes": routes,
		"count":  len(routes),
	})
}

func (h *RoutingHandler) GetAvailableModes(w http.ResponseWriter, r *http.Request) {
	modes := []models.TransportMode{
		models.Bixi,
		models.Biking,
		models.Car,
		models.PublicTransit,
		models.Walking,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"modes": modes,
	})
}
