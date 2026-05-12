package web

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func newHistoryTestServer(t *testing.T) (Server, string) {
	t.Helper()
	dir := t.TempDir()
	store := NewSessionStore()
	return Server{
		Sessions:   store,
		ConfigPath: filepath.Join(dir, "config.json"),
	}, dir
}

func bearerRequest(method, path, token string, body []byte) *http.Request {
	var req *http.Request
	if body == nil {
		req = httptest.NewRequest(method, path, nil)
	} else {
		req = httptest.NewRequest(method, path, bytes.NewReader(body))
	}
	req.Header.Set("Authorization", "Bearer "+token)
	return req
}

func TestHandleHistoryRejectsAnonymous(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	req := httptest.NewRequest(http.MethodGet, "/api/history", nil)
	rr := httptest.NewRecorder()
	s.handleHistory(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous GET: got %d want 401; body=%s", rr.Code, rr.Body.String())
	}
}

func TestHandleHistoryPutCreatesEntry(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, err := s.Sessions.Create("alice", "user")
	if err != nil {
		t.Fatalf("session: %v", err)
	}

	body := []byte(`{"file_id":"f1","bangumi_title":"Frieren","episode":"01","position_sec":120,"duration_sec":1440}`)
	req := bearerRequest(http.MethodPut, "/api/history", token, body)
	rr := httptest.NewRecorder()
	s.handleHistory(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("PUT: got %d want 200; body=%s", rr.Code, rr.Body.String())
	}

	// GET should now return that entry.
	getReq := bearerRequest(http.MethodGet, "/api/history", token, nil)
	getRR := httptest.NewRecorder()
	s.handleHistory(getRR, getReq)
	if getRR.Code != http.StatusOK {
		t.Fatalf("GET: got %d", getRR.Code)
	}
	var got struct {
		Entries []HistoryEntry `json:"entries"`
	}
	if err := json.Unmarshal(getRR.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(got.Entries) != 1 || got.Entries[0].FileID != "f1" || got.Entries[0].PositionSec != 120 {
		t.Fatalf("unexpected entries: %+v", got.Entries)
	}
	if got.Entries[0].UpdatedAt <= 0 {
		t.Fatalf("UpdatedAt should be auto-stamped, got %d", got.Entries[0].UpdatedAt)
	}
}

func TestHandleHistoryPutUpdatesSameFileID(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("bob", "user")

	for _, pos := range []int{30, 60, 120} {
		body, _ := json.Marshal(HistoryEntry{FileID: "f1", BangumiTitle: "X", PositionSec: pos})
		rr := httptest.NewRecorder()
		s.handleHistory(rr, bearerRequest(http.MethodPut, "/api/history", token, body))
		if rr.Code != http.StatusOK {
			t.Fatalf("put pos=%d: %d", pos, rr.Code)
		}
	}

	rr := httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodGet, "/api/history", token, nil))
	var got struct {
		Entries []HistoryEntry `json:"entries"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &got)
	if len(got.Entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(got.Entries))
	}
	if got.Entries[0].PositionSec != 120 {
		t.Fatalf("expected latest position 120, got %d", got.Entries[0].PositionSec)
	}
}

func TestHandleHistoryUsersAreIsolated(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	aliceTok, _, _ := s.Sessions.Create("alice", "user")
	bobTok, _, _ := s.Sessions.Create("bob", "user")

	bodyA, _ := json.Marshal(HistoryEntry{FileID: "fa", BangumiTitle: "AliceWatch"})
	bodyB, _ := json.Marshal(HistoryEntry{FileID: "fb", BangumiTitle: "BobWatch"})
	s.handleHistory(httptest.NewRecorder(), bearerRequest(http.MethodPut, "/api/history", aliceTok, bodyA))
	s.handleHistory(httptest.NewRecorder(), bearerRequest(http.MethodPut, "/api/history", bobTok, bodyB))

	rrA := httptest.NewRecorder()
	s.handleHistory(rrA, bearerRequest(http.MethodGet, "/api/history", aliceTok, nil))
	rrB := httptest.NewRecorder()
	s.handleHistory(rrB, bearerRequest(http.MethodGet, "/api/history", bobTok, nil))

	var ga, gb struct {
		Entries []HistoryEntry `json:"entries"`
	}
	_ = json.Unmarshal(rrA.Body.Bytes(), &ga)
	_ = json.Unmarshal(rrB.Body.Bytes(), &gb)
	if len(ga.Entries) != 1 || ga.Entries[0].FileID != "fa" {
		t.Fatalf("alice should see only her entry, got %+v", ga.Entries)
	}
	if len(gb.Entries) != 1 || gb.Entries[0].FileID != "fb" {
		t.Fatalf("bob should see only his entry, got %+v", gb.Entries)
	}
}

func TestHandleHistoryPutRejectsEmptyFileID(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")

	rr := httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodPut, "/api/history", token, []byte(`{"bangumi_title":"X"}`)))
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing file_id, got %d", rr.Code)
	}
}

func TestHandleHistoryRejectsUnsupportedMethod(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")

	rr := httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodPatch, "/api/history", token, nil))
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rr.Code)
	}
}

func TestHandleHistoryDeleteSingleEntryByFileID(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")

	for _, fid := range []string{"f1", "f2"} {
		body, _ := json.Marshal(HistoryEntry{FileID: fid, BangumiTitle: "X"})
		rr := httptest.NewRecorder()
		s.handleHistory(rr, bearerRequest(http.MethodPut, "/api/history", token, body))
		if rr.Code != http.StatusOK {
			t.Fatalf("seed %s: %d", fid, rr.Code)
		}
	}

	// DELETE with file_id removes only that one entry.
	rr := httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodDelete, "/api/history?file_id=f1", token, nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("delete f1: %d", rr.Code)
	}

	rr = httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodGet, "/api/history", token, nil))
	var got struct {
		Entries []HistoryEntry `json:"entries"`
	}
	_ = json.Unmarshal(rr.Body.Bytes(), &got)
	if len(got.Entries) != 1 || got.Entries[0].FileID != "f2" {
		t.Fatalf("expected only f2 to remain, got %+v", got.Entries)
	}
}

func TestHandleHistoryDeleteClearsAll(t *testing.T) {
	s, _ := newHistoryTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")

	// Seed one entry.
	body := []byte(`{"file_id":"f1","bangumi_title":"Frieren","position_sec":120,"duration_sec":1440}`)
	rr := httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodPut, "/api/history", token, body))
	if rr.Code != http.StatusOK {
		t.Fatalf("seed put: got %d", rr.Code)
	}

	// DELETE.
	rr = httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodDelete, "/api/history", token, nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("delete: got %d", rr.Code)
	}

	// GET should now return empty.
	rr = httptest.NewRecorder()
	s.handleHistory(rr, bearerRequest(http.MethodGet, "/api/history", token, nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("get after delete: got %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), `"entries":[]`) {
		t.Fatalf("expected empty entries, got %s", rr.Body.String())
	}
}
