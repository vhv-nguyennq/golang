package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
)

type Product struct {
	ID    int     `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

type ProductInput struct {
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

type Store struct {
	mu       sync.RWMutex
	products map[int]Product
	nextID   int
}

func NewStore() *Store {
	return &Store{products: make(map[int]Product), nextID: 1}
}

func (s *Store) list() []Product {
	s.mu.RLock()
	defer s.mu.RUnlock()

	items := make([]Product, 0, len(s.products))
	for _, p := range s.products {
		items = append(items, p)
	}
	return items
}

func (s *Store) create(in ProductInput) Product {
	s.mu.Lock()
	defer s.mu.Unlock()

	p := Product{ID: s.nextID, Name: in.Name, Price: in.Price}
	s.products[p.ID] = p
	s.nextID++
	return p
}

func (s *Store) get(id int) (Product, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.products[id]
	return p, ok
}

func (s *Store) update(id int, in ProductInput) (Product, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.products[id]; !ok {
		return Product{}, false
	}
	p := Product{ID: id, Name: in.Name, Price: in.Price}
	s.products[id] = p
	return p, true
}

func (s *Store) delete(id int) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.products[id]; !ok {
		return false
	}
	delete(s.products, id)
	return true
}

type Server struct {
	store *Store
}

func NewServer() *Server {
	return &Server{store: NewStore()}
}

func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/products", s.handleProducts)
	mux.HandleFunc("/products/", s.handleProductByID)
	return mux
}

func (s *Server) handleProducts(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.store.list())
	case http.MethodPost:
		var in ProductInput
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeError(w, http.StatusBadRequest, "invalid json")
			return
		}
		if strings.TrimSpace(in.Name) == "" || in.Price < 0 {
			writeError(w, http.StatusBadRequest, "name is required and price must be >= 0")
			return
		}
		writeJSON(w, http.StatusCreated, s.store.create(in))
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (s *Server) handleProductByID(w http.ResponseWriter, r *http.Request) {
	idStr := strings.TrimPrefix(r.URL.Path, "/products/")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}

	switch r.Method {
	case http.MethodGet:
		p, ok := s.store.get(id)
		if !ok {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		writeJSON(w, http.StatusOK, p)
	case http.MethodPut:
		var in ProductInput
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeError(w, http.StatusBadRequest, "invalid json")
			return
		}
		if strings.TrimSpace(in.Name) == "" || in.Price < 0 {
			writeError(w, http.StatusBadRequest, "name is required and price must be >= 0")
			return
		}
		p, ok := s.store.update(id, in)
		if !ok {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		writeJSON(w, http.StatusOK, p)
	case http.MethodDelete:
		if ok := s.store.delete(id); !ok {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func main() {
	srv := NewServer()
	log.Println("CRUD API running at http://localhost:8080")
	if err := http.ListenAndServe(":8080", srv.routes()); err != nil {
		log.Fatal(err)
	}
}
