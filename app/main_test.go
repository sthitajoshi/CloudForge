package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	newMux().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestCreateAndListItems(t *testing.T) {
	mux := newMux()

	body, _ := json.Marshal(Item{ID: "1", Name: "widget"})
	postReq := httptest.NewRequest(http.MethodPost, "/items", bytes.NewReader(body))
	postRec := httptest.NewRecorder()
	mux.ServeHTTP(postRec, postReq)

	if postRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", postRec.Code)
	}

	getReq := httptest.NewRequest(http.MethodGet, "/items", nil)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	var items []Item
	if err := json.Unmarshal(getRec.Body.Bytes(), &items); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(items) != 1 || items[0].ID != "1" {
		t.Fatalf("expected 1 item with id 1, got %+v", items)
	}
}

func TestCreateItemInvalid(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/items", bytes.NewReader([]byte(`{}`)))
	rec := httptest.NewRecorder()

	newMux().ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}
