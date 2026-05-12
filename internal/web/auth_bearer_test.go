package web

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAuthenticatedUserAcceptsBearerToken(t *testing.T) {
	store := NewSessionStore()
	token, _, err := store.Create("alice", "user")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	s := Server{Sessions: store}

	req := httptest.NewRequest(http.MethodGet, "/api/library", nil)
	req.Header.Set("Authorization", "Bearer "+token)

	user, ok := s.authenticatedUser(req)
	if !ok {
		t.Fatalf("expected ok=true with valid bearer token")
	}
	if user.Username != "alice" {
		t.Fatalf("username: got %q want alice", user.Username)
	}
}

func TestAuthenticatedUserStillReadsCookie(t *testing.T) {
	store := NewSessionStore()
	token, _, err := store.Create("bob", "admin")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	s := Server{Sessions: store}

	req := httptest.NewRequest(http.MethodGet, "/api/library", nil)
	req.AddCookie(&http.Cookie{Name: authCookieName, Value: token})

	user, ok := s.authenticatedUser(req)
	if !ok || user.Username != "bob" {
		t.Fatalf("cookie path broken: ok=%v user=%+v", ok, user)
	}
}

func TestAuthenticatedUserRejectsBogusBearer(t *testing.T) {
	store := NewSessionStore()
	s := Server{Sessions: store}

	req := httptest.NewRequest(http.MethodGet, "/api/library", nil)
	req.Header.Set("Authorization", "Bearer not-a-real-token")

	_, ok := s.authenticatedUser(req)
	if ok {
		t.Fatalf("expected ok=false for invalid bearer")
	}
}

func TestAuthenticatedUserCaseInsensitiveBearerPrefix(t *testing.T) {
	store := NewSessionStore()
	token, _, err := store.Create("carol", "user")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	s := Server{Sessions: store}

	req := httptest.NewRequest(http.MethodGet, "/api/library", nil)
	req.Header.Set("Authorization", "bearer "+token) // lower-case scheme

	user, ok := s.authenticatedUser(req)
	if !ok || user.Username != "carol" {
		t.Fatalf("expected case-insensitive bearer to work: ok=%v user=%+v", ok, user)
	}
}
