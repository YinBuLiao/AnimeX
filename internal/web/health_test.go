package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"bangumi-pikpak/internal/config"
)

func TestHandleHealthReturnsVersion(t *testing.T) {
	s := Server{Version: "test-v1", Runtime: nil} // Runtime nil => installed=false
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
		t.Fatalf("expected installed=false when Runtime is nil; got true")
	}
}

func TestHandleHealthReturnsInstalledTrue(t *testing.T) {
	s := Server{
		Version: "test-v1",
		Runtime: &RuntimeState{Installed: true},
	}
	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rr := httptest.NewRecorder()
	s.handleHealth(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	var body struct {
		OK        bool `json:"ok"`
		Installed bool `json:"installed"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !body.OK || !body.Installed {
		t.Fatalf("expected installed=true; got %+v", body)
	}
}

func TestHealthBypassesInstallLock(t *testing.T) {
	// Regression: /api/health must be reachable BEFORE the install wizard
	// has completed so the mobile app can probe the server URL. The
	// installLockMiddleware must let /api/health through even when
	// installed=false / InstallOnly=true.
	tmpDB := filepath.Join(t.TempDir(), "config.db")
	s := Server{
		Version:      "test-v1",
		InstallOnly:  true,
		ConfigDBPath: tmpDB,
	}
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/health")
	if err != nil {
		t.Fatalf("GET /api/health: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: got %d want 200 (install lock should not block /api/health)", resp.StatusCode)
	}
	var body struct {
		OK        bool   `json:"ok"`
		Version   string `json:"version"`
		Installed bool   `json:"installed"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if !body.OK || body.Version != "test-v1" || body.Installed {
		t.Fatalf("bad body: %+v", body)
	}
}

func TestHealthBypassesAuthMiddleware(t *testing.T) {
	// Regression: /api/health must remain anonymous even after the system is
	// fully installed with RequireLogin=true. The mobile app keeps polling
	// /api/health from the server-setup page (e.g. after "更换服务器") so the
	// authMiddleware must let it through without a session cookie / Bearer.
	tmpDB := filepath.Join(t.TempDir(), "config.db")
	s := Server{
		Version:      "test-v1",
		ConfigDBPath: tmpDB,
		Runtime: NewRuntimeState(
			config.Config{RequireLogin: true},
			true,  // installed
			false, // installOnly
			nil, nil, nil, nil, nil,
		),
	}
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/health")
	if err != nil {
		t.Fatalf("GET /api/health: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status: got %d want 200 (auth middleware should not block /api/health)", resp.StatusCode)
	}
	var body struct {
		OK        bool `json:"ok"`
		Installed bool `json:"installed"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if !body.OK || !body.Installed {
		t.Fatalf("bad body: %+v", body)
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
