package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func newNotifyTestServer(t *testing.T) Server {
	t.Helper()
	dir := t.TempDir()
	return Server{
		Sessions:   NewSessionStore(),
		ConfigPath: filepath.Join(dir, "config.json"),
	}
}

func TestNotificationsRejectsAnonymous(t *testing.T) {
	s := newNotifyTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/api/notifications", nil)
	rr := httptest.NewRecorder()
	s.handleNotifications(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("got %d want 401; body=%s", rr.Code, rr.Body.String())
	}
}

func TestNotificationsListReturnsEmpty(t *testing.T) {
	s := newNotifyTestServer(t)
	token, _, err := s.Sessions.Create("alice", "user")
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	req := bearerRequest(http.MethodGet, "/api/notifications", token, nil)
	rr := httptest.NewRecorder()
	s.handleNotifications(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	var out struct {
		Entries []Notification `json:"entries"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(out.Entries) != 0 {
		t.Fatalf("expected empty list, got %d", len(out.Entries))
	}
}

func TestNotificationsAppendThenListNewestFirst(t *testing.T) {
	s := newNotifyTestServer(t)
	store := s.notificationsStore()
	if _, err := store.append("alice", Notification{
		Kind: NotificationKindRequestApproved, Title: "申请通过",
		CreatedAt: 100,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.append("alice", Notification{
		Kind: NotificationKindNewEpisode, Title: "新剧集",
		CreatedAt: 200,
	}); err != nil {
		t.Fatal(err)
	}
	entries, err := store.list("alice", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2", len(entries))
	}
	if entries[0].Kind != NotificationKindNewEpisode {
		t.Fatalf("expected newest first; got %s", entries[0].Kind)
	}
}

func TestNotificationsListFiltersBySince(t *testing.T) {
	s := newNotifyTestServer(t)
	store := s.notificationsStore()
	for i, ts := range []int64{100, 200, 300} {
		_, err := store.append("bob", Notification{
			Kind: "x", Title: "n", CreatedAt: ts,
		})
		if err != nil {
			t.Fatalf("seed %d: %v", i, err)
		}
	}
	entries, err := store.list("bob", 150)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("got %d, want 2 (after ts=150)", len(entries))
	}
	for _, e := range entries {
		if e.CreatedAt <= 150 {
			t.Fatalf("entry %v should be filtered by since", e)
		}
	}
}

func TestNotificationsIsolatedAcrossUsers(t *testing.T) {
	s := newNotifyTestServer(t)
	store := s.notificationsStore()
	_, _ = store.append("alice", Notification{Title: "for-alice", CreatedAt: 100})
	_, _ = store.append("bob", Notification{Title: "for-bob", CreatedAt: 100})
	aliceList, _ := store.list("alice", 0)
	bobList, _ := store.list("bob", 0)
	if len(aliceList) != 1 || aliceList[0].Title != "for-alice" {
		t.Fatalf("alice mismatch: %+v", aliceList)
	}
	if len(bobList) != 1 || bobList[0].Title != "for-bob" {
		t.Fatalf("bob mismatch: %+v", bobList)
	}
}

func TestNotificationsRejectsInvalidSince(t *testing.T) {
	s := newNotifyTestServer(t)
	token, _, err := s.Sessions.Create("alice", "user")
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	req := bearerRequest(http.MethodGet, "/api/notifications?since=abc", token, nil)
	rr := httptest.NewRecorder()
	s.handleNotifications(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("got %d want 400", rr.Code)
	}
}

func TestNotificationsRejectsNonGet(t *testing.T) {
	s := newNotifyTestServer(t)
	token, _, err := s.Sessions.Create("alice", "user")
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	req := bearerRequest(http.MethodPost, "/api/notifications", token, []byte(`{}`))
	rr := httptest.NewRecorder()
	s.handleNotifications(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("got %d want 405", rr.Code)
	}
}
