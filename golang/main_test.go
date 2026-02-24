package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestProductCRUDFlow(t *testing.T) {
	s := NewServer()
	h := s.routes()

	// Create
	body := bytes.NewBufferString(`{"name":"Keyboard","price":99.5}`)
	req := httptest.NewRequest(http.MethodPost, "/products", body)
	res := httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", res.Code)
	}

	var created Product
	if err := json.NewDecoder(res.Body).Decode(&created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	if created.ID != 1 || created.Name != "Keyboard" {
		t.Fatalf("unexpected create result: %+v", created)
	}

	// Get by ID
	req = httptest.NewRequest(http.MethodGet, "/products/1", nil)
	res = httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}

	// Update
	updateBody := bytes.NewBufferString(`{"name":"Mechanical Keyboard","price":120}`)
	req = httptest.NewRequest(http.MethodPut, "/products/1", updateBody)
	res = httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}

	// List
	req = httptest.NewRequest(http.MethodGet, "/products", nil)
	res = httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.Code)
	}
	var items []Product
	if err := json.NewDecoder(res.Body).Decode(&items); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	if len(items) != 1 || items[0].Name != "Mechanical Keyboard" {
		t.Fatalf("unexpected list items: %+v", items)
	}

	// Delete
	req = httptest.NewRequest(http.MethodDelete, "/products/1", nil)
	res = httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", res.Code)
	}

	// Confirm deleted
	req = httptest.NewRequest(http.MethodGet, "/products/1", nil)
	res = httptest.NewRecorder()
	h.ServeHTTP(res, req)
	if res.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", res.Code)
	}
}
