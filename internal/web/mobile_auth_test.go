package web

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"bangumi-pikpak/internal/config"
)

func newMobileLoginTestServer() Server {
	cfg := config.Config{AdminUsername: "alice", AdminPassword: "secret"}
	return Server{
		Config:   cfg,
		Sessions: NewSessionStore(),
	}
}

func TestHandleMobileLoginReturnsTokenOnSuccess(t *testing.T) {
	s := newMobileLoginTestServer()

	body, _ := json.Marshal(map[string]string{"username": "alice", "password": "secret"})
	req := httptest.NewRequest(http.MethodPost, "/api/auth/mobile-login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	var resp struct {
		OK        bool   `json:"ok"`
		Token     string `json:"token"`
		ExpiresAt int64  `json:"expires_at"`
		Username  string `json:"username"`
		Role      string `json:"role"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !resp.OK || resp.Token == "" || resp.Username != "alice" || resp.Role != "admin" {
		t.Fatalf("bad response: %+v", resp)
	}
	if resp.ExpiresAt <= 0 {
		t.Fatalf("expires_at not set: %d", resp.ExpiresAt)
	}
	if _, ok := s.Sessions.User(resp.Token); !ok {
		t.Fatalf("token not stored in session store")
	}
	// Cookie MUST NOT be set on mobile-login (this is the differentiator vs /api/auth/login)
	if len(rr.Result().Cookies()) != 0 {
		t.Fatalf("mobile-login set a cookie; should not: %v", rr.Result().Cookies())
	}
}

func TestHandleMobileLoginRejectsBadPassword(t *testing.T) {
	s := newMobileLoginTestServer()

	body, _ := json.Marshal(map[string]string{"username": "alice", "password": "WRONG"})
	req := httptest.NewRequest(http.MethodPost, "/api/auth/mobile-login", bytes.NewReader(body))
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401; body=%s", rr.Code, rr.Body.String())
	}
}

func TestHandleMobileLoginRejectsNonPOST(t *testing.T) {
	s := newMobileLoginTestServer()
	req := httptest.NewRequest(http.MethodGet, "/api/auth/mobile-login", nil)
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status: got %d want 405", rr.Code)
	}
	if allow := rr.Header().Get("Allow"); allow != http.MethodPost {
		t.Fatalf("Allow header: got %q want %q", allow, http.MethodPost)
	}
}

func TestHandleMobileLoginRejectsBadJSON(t *testing.T) {
	s := newMobileLoginTestServer()
	req := httptest.NewRequest(http.MethodPost, "/api/auth/mobile-login",
		bytes.NewReader([]byte("not json")))
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d want 400", rr.Code)
	}
}
