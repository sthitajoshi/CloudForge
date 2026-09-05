package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
)

type Item struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type store struct {
	mu    sync.Mutex
	items map[string]Item
}

func newStore() *store {
	return &store{items: make(map[string]Item)}
}

func (s *store) handleItems(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.mu.Lock()
		defer s.mu.Unlock()
		list := make([]Item, 0, len(s.items))
		for _, item := range s.items {
			list = append(list, item)
		}
		writeJSON(w, http.StatusOK, list)

	case http.MethodPost:
		var item Item
		if err := json.NewDecoder(r.Body).Decode(&item); err != nil || item.ID == "" {
			http.Error(w, "invalid item", http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		s.items[item.ID] = item
		s.mu.Unlock()
		writeJSON(w, http.StatusCreated, item)

	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func newMux() *http.ServeMux {
	s := newStore()
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/items", s.handleItems)
	return mux
}

func main() {
	log.Println("listening on :8080")
	if err := http.ListenAndServe(":8080", newMux()); err != nil {
		log.Fatal(err)
	}
}
