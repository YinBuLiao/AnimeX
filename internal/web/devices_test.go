package web

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func newDevicesTestServer(t *testing.T) Server {
	t.Helper()
	dir := t.TempDir()
	return Server{
		Sessions:   NewSessionStore(),
		ConfigPath: filepath.Join(dir, "config.json"),
	}
}

func TestDeviceRegisterRejectsAnonymous(t *testing.T) {
	s := newDevicesTestServer(t)
	req := httptest.NewRequest(http.MethodPost, "/api/devices/register",
		bytes.NewReader([]byte(`{"fcm_token":"abc","platform":"ios"}`)))
	rr := httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("got %d want 401", rr.Code)
	}
}

func TestDeviceRegisterRequiresFcmToken(t *testing.T) {
	s := newDevicesTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")
	req := bearerRequest(http.MethodPost, "/api/devices/register", token,
		[]byte(`{"fcm_token":"","platform":"android"}`))
	rr := httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("got %d want 400; body=%s", rr.Code, rr.Body.String())
	}
}

func TestDeviceRegisterRequiresValidPlatform(t *testing.T) {
	s := newDevicesTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")
	req := bearerRequest(http.MethodPost, "/api/devices/register", token,
		[]byte(`{"fcm_token":"t1","platform":"windows"}`))
	rr := httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("got %d want 400", rr.Code)
	}
}

func TestDeviceRegisterAndQuery(t *testing.T) {
	s := newDevicesTestServer(t)
	token, _, _ := s.Sessions.Create("alice", "user")
	req := bearerRequest(http.MethodPost, "/api/devices/register", token,
		[]byte(`{"fcm_token":"tok-alice-1","platform":"android"}`))
	rr := httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	devs, err := s.deviceStore().tokensFor("alice")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(devs) != 1 || devs[0].FcmToken != "tok-alice-1" {
		t.Fatalf("unexpected: %+v", devs)
	}
}

func TestDeviceRegisterIdempotentRebind(t *testing.T) {
	s := newDevicesTestServer(t)
	// Initial registration by alice.
	aliceTok, _, _ := s.Sessions.Create("alice", "user")
	req := bearerRequest(http.MethodPost, "/api/devices/register", aliceTok,
		[]byte(`{"fcm_token":"shared","platform":"ios"}`))
	rr := httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	// Same FCM token re-registered by bob (e.g. user switched accounts).
	bobTok, _, _ := s.Sessions.Create("bob", "user")
	req = bearerRequest(http.MethodPost, "/api/devices/register", bobTok,
		[]byte(`{"fcm_token":"shared","platform":"ios"}`))
	rr = httptest.NewRecorder()
	s.handleDeviceRegister(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("re-register: got %d want 200", rr.Code)
	}
	aliceDevs, _ := s.deviceStore().tokensFor("alice")
	bobDevs, _ := s.deviceStore().tokensFor("bob")
	if len(aliceDevs) != 0 {
		t.Fatalf("alice should have 0 devices after rebind, got %d", len(aliceDevs))
	}
	if len(bobDevs) != 1 {
		t.Fatalf("bob should have 1 device after rebind, got %d", len(bobDevs))
	}
}

func TestDeviceUnregisterRemovesEntry(t *testing.T) {
	s := newDevicesTestServer(t)
	tok, _, _ := s.Sessions.Create("alice", "user")
	req := bearerRequest(http.MethodPost, "/api/devices/register", tok,
		[]byte(`{"fcm_token":"t-x","platform":"android"}`))
	s.handleDeviceRegister(httptest.NewRecorder(), req)

	req = bearerRequest(http.MethodPost, "/api/devices/unregister", tok,
		[]byte(`{"fcm_token":"t-x"}`))
	rr := httptest.NewRecorder()
	s.handleDeviceUnregister(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("got %d want 200", rr.Code)
	}
	devs, _ := s.deviceStore().tokensFor("alice")
	if len(devs) != 0 {
		t.Fatalf("expected 0 devices after unregister, got %d", len(devs))
	}
}
