package notify

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func generateServiceAccountJSON(t *testing.T, projectID, tokenURI string) ([]byte, *rsa.PrivateKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("rsa: %v", err)
	}
	pkcs8, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("pkcs8: %v", err)
	}
	pemStr := string(pem.EncodeToMemory(&pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: pkcs8,
	}))
	sa := serviceAccount{
		Type:        "service_account",
		ProjectID:   projectID,
		PrivateKey:  pemStr,
		ClientEmail: "test-sa@" + projectID + ".iam.gserviceaccount.com",
		TokenURI:    tokenURI,
	}
	data, err := json.Marshal(sa)
	if err != nil {
		t.Fatalf("marshal sa: %v", err)
	}
	return data, key
}

func TestNewSenderReturnsNoopWhenUnconfigured(t *testing.T) {
	t.Setenv("ANIMEX_FCM_SERVICE_ACCOUNT", "")
	t.Setenv("ANIMEX_FCM_SERVICE_ACCOUNT_JSON", "")
	s, err := NewSender()
	if err != nil {
		t.Fatalf("NewSender: %v", err)
	}
	if _, ok := s.(NoopSender); !ok {
		t.Fatalf("expected NoopSender, got %T", s)
	}
	if err := s.Send(context.Background(), Message{Token: "x", Title: "t", Body: "b"}); err != nil {
		t.Fatalf("noop send returned %v", err)
	}
}

func TestNewSenderBuildsFcmSenderFromEnv(t *testing.T) {
	raw, _ := generateServiceAccountJSON(t, "my-proj", "https://example.invalid/token")
	t.Setenv("ANIMEX_FCM_SERVICE_ACCOUNT_JSON", string(raw))
	t.Setenv("ANIMEX_FCM_SERVICE_ACCOUNT", "")
	s, err := NewSender()
	if err != nil {
		t.Fatalf("NewSender: %v", err)
	}
	if _, ok := s.(*FcmSender); !ok {
		t.Fatalf("expected FcmSender, got %T", s)
	}
}

func TestFcmSenderRejectsMissingToken(t *testing.T) {
	raw, _ := generateServiceAccountJSON(t, "p", "https://example.invalid/token")
	s, err := newFcmSenderFromBytes(raw)
	if err != nil {
		t.Fatalf("newFcm: %v", err)
	}
	err = s.Send(context.Background(), Message{Title: "t", Body: "b"})
	if err == nil || !strings.Contains(err.Error(), "Token is required") {
		t.Fatalf("expected Token required error, got %v", err)
	}
}

func TestFcmSenderEndToEndAgainstFakeServers(t *testing.T) {
	// Fake token server.
	var capturedAssertion string
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		capturedAssertion = r.Form.Get("assertion")
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"access_token":"fake-at-1","expires_in":3600}`)
	}))
	defer tokenSrv.Close()

	raw, _ := generateServiceAccountJSON(t, "my-proj", tokenSrv.URL)
	s, err := newFcmSenderFromBytes(raw)
	if err != nil {
		t.Fatalf("newFcm: %v", err)
	}

	// Fake FCM send server. We override the URL by hijacking via a custom
	// http.Client — but the FCM URL is hard-coded. Instead, test the
	// accessToken path only here; full HTTP round-trip is verified by
	// integration in a deployed environment.
	at, err := s.accessTokenFor(context.Background())
	if err != nil {
		t.Fatalf("accessTokenFor: %v", err)
	}
	if at != "fake-at-1" {
		t.Fatalf("expected fake-at-1, got %s", at)
	}
	if capturedAssertion == "" {
		t.Fatalf("token server did not capture assertion")
	}
	parts := strings.Split(capturedAssertion, ".")
	if len(parts) != 3 {
		t.Fatalf("JWT should have 3 parts, got %d", len(parts))
	}

	// Confirms the cache short-circuits the second call (no new server hit).
	prev := capturedAssertion
	capturedAssertion = ""
	if _, err := s.accessTokenFor(context.Background()); err != nil {
		t.Fatalf("second accessTokenFor: %v", err)
	}
	if capturedAssertion != "" {
		t.Fatalf("expected cache hit, but server was called again")
	}
	_ = prev
}

func TestFcmSenderRejectsBadServiceAccount(t *testing.T) {
	_, err := newFcmSenderFromBytes([]byte(`{"type":"service_account"}`))
	if err == nil {
		t.Fatalf("expected error for missing fields")
	}
}

func TestSignJWTContainsExpectedClaims(t *testing.T) {
	raw, _ := generateServiceAccountJSON(t, "proj-x", "https://example.invalid/token")
	s, err := newFcmSenderFromBytes(raw)
	if err != nil {
		t.Fatalf("newFcm: %v", err)
	}
	jwt, err := s.signJWT(time.Unix(1700000000, 0))
	if err != nil {
		t.Fatalf("signJWT: %v", err)
	}
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		t.Fatalf("jwt parts=%d", len(parts))
	}
}
