package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleHealthReturnsVersion(t *testing.T) {
	s := Server{Version: "test-v1"} // LocalDB nil => installed=false
	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rr := httptest.NewRecorder()
	s.handleHealth(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	if ct := rr.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("content-type: got %q", ct)
	}
	var body struct {
		OK        bool   `json:"ok"`
		Version   string `json:"version"`
		Installed bool   `json:"installed"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !body.OK || body.Version != "test-v1" {
		t.Fatalf("bad body: %+v", body)
	}
	if body.Installed {
		t.Fatalf("expected installed=false when LocalDB is nil; got true")
	}
}

func TestHandleHealthRejectsNonGET(t *testing.T) {
	s := Server{}
	req := httptest.NewRequest(http.MethodPost, "/api/health", nil)
	rr := httptest.NewRecorder()
	s.handleHealth(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status: got %d want 405", rr.Code)
	}
	if allow := rr.Header().Get("Allow"); allow != http.MethodGet {
		t.Fatalf("Allow header: got %q want %q", allow, http.MethodGet)
	}
}
