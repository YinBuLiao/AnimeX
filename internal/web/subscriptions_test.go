package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleSubscriptionsListRejectsAnonymous(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/api/subscriptions", nil)
	rr := httptest.NewRecorder()
	s.handleSubscriptionsList(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous: got %d want 401; body=%s", rr.Code, rr.Body.String())
	}
}

func TestHandleSubscriptionsListReturnsEmptyWithoutStore(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")

	req := bearerRequest(http.MethodGet, "/api/subscriptions", token, nil)
	rr := httptest.NewRecorder()
	s.handleSubscriptionsList(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("got %d; body=%s", rr.Code, rr.Body.String())
	}
	var got struct {
		Titles []string `json:"titles"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Titles) != 0 {
		t.Fatalf("want empty titles, got %+v", got.Titles)
	}
	if !strings.Contains(rr.Body.String(), `"titles":[]`) {
		t.Fatalf("want explicit empty array, body=%s", rr.Body.String())
	}
}

func TestHandleSubscriptionsListRejectsUnsupportedMethod(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")
	rr := httptest.NewRecorder()
	s.handleSubscriptionsList(rr, bearerRequest(http.MethodPost, "/api/subscriptions", token, nil))
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rr.Code)
	}
}
