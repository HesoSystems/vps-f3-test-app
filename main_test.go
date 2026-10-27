package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRootShowsVersion(t *testing.T) {
	version = "abc123"
	rec := httptest.NewRecorder()
	handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "abc123") {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if healthy && rec.Code != http.StatusOK {
		t.Fatalf("healthy build must answer 200, got %d", rec.Code)
	}
	if !healthy && rec.Code != http.StatusInternalServerError {
		t.Fatalf("broken build must answer 500, got %d", rec.Code)
	}
}

func TestProbe(t *testing.T) {
	srv := httptest.NewServer(handler())
	defer srv.Close()
	want := 0
	if !healthy {
		want = 1
	}
	if got := probe(srv.URL + "/healthz"); got != want {
		t.Fatalf("probe = %d, want %d", got, want)
	}
}
