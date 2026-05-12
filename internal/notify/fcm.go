// Package notify implements outbound push notifications.
//
// FCM v1 HTTP integration with stdlib-only JWT signing. When no service
// account is configured (env unset or file missing) the sender no-ops so
// AnimeX runs cleanly without a Firebase project — useful for self-hosted
// deployments that only want the in-app notification center.
package notify

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	tokenURI    = "https://oauth2.googleapis.com/token"
	fcmScope    = "https://www.googleapis.com/auth/firebase.messaging"
	tokenGrant  = "urn:ietf:params:oauth:grant-type:jwt-bearer"
	jwtLifetime = time.Hour
)

// Message is a vendor-neutral push payload.
type Message struct {
	Token string            // destination FCM device token
	Title string            // notification title
	Body  string            // notification body
	Data  map[string]string // optional data payload (deep-link, kind, ids…)
}

// Sender dispatches push messages.
type Sender interface {
	Send(ctx context.Context, msg Message) error
}

// NoopSender is the zero-config implementation used when no service
// account is configured. Send returns nil silently.
type NoopSender struct{}

func (NoopSender) Send(_ context.Context, _ Message) error { return nil }

type serviceAccount struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
	TokenURI    string `json:"token_uri"`
}

// FcmSender posts to Firebase Cloud Messaging v1 using a Google service
// account for OAuth.
type FcmSender struct {
	sa         serviceAccount
	privateKey *rsa.PrivateKey
	httpClient *http.Client

	mu          sync.Mutex
	accessToken string
	expiresAt   time.Time
}

// NewSender constructs the configured Sender, picking the FCM
// implementation when ANIMEX_FCM_SERVICE_ACCOUNT or
// ANIMEX_FCM_SERVICE_ACCOUNT_JSON resolves, otherwise NoopSender.
func NewSender() (Sender, error) {
	raw, source, err := loadServiceAccount()
	if err != nil {
		return nil, err
	}
	if raw == nil {
		return NoopSender{}, nil
	}
	s, err := newFcmSenderFromBytes(raw)
	if err != nil {
		return nil, fmt.Errorf("load FCM service account (%s): %w", source, err)
	}
	return s, nil
}

func loadServiceAccount() ([]byte, string, error) {
	if raw := strings.TrimSpace(os.Getenv("ANIMEX_FCM_SERVICE_ACCOUNT_JSON")); raw != "" {
		return []byte(raw), "ANIMEX_FCM_SERVICE_ACCOUNT_JSON", nil
	}
	if path := strings.TrimSpace(os.Getenv("ANIMEX_FCM_SERVICE_ACCOUNT")); path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, path, err
		}
		return data, path, nil
	}
	return nil, "", nil
}

func newFcmSenderFromBytes(raw []byte) (*FcmSender, error) {
	var sa serviceAccount
	if err := json.Unmarshal(raw, &sa); err != nil {
		return nil, fmt.Errorf("invalid JSON: %w", err)
	}
	if sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("missing project_id / client_email / private_key")
	}
	if sa.TokenURI == "" {
		sa.TokenURI = tokenURI
	}
	key, err := parseRSAPrivateKey(sa.PrivateKey)
	if err != nil {
		return nil, err
	}
	return &FcmSender{
		sa:         sa,
		privateKey: key,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}, nil
}

func parseRSAPrivateKey(pemStr string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, errors.New("private_key is not PEM encoded")
	}
	if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return k, nil
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse PKCS8 key: %w", err)
	}
	rsaKey, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("private_key is not an RSA key")
	}
	return rsaKey, nil
}

// Send dispatches the message via FCM v1.
func (s *FcmSender) Send(ctx context.Context, msg Message) error {
	if strings.TrimSpace(msg.Token) == "" {
		return errors.New("Message.Token is required")
	}
	token, err := s.accessTokenFor(ctx)
	if err != nil {
		return err
	}
	body := map[string]any{
		"message": map[string]any{
			"token": msg.Token,
			"notification": map[string]any{
				"title": msg.Title,
				"body":  msg.Body,
			},
		},
	}
	if len(msg.Data) > 0 {
		body["message"].(map[string]any)["data"] = msg.Data
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	endpoint := fmt.Sprintf(
		"https://fcm.googleapis.com/v1/projects/%s/messages:send",
		s.sa.ProjectID,
	)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	res, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 400 {
		respBody, _ := io.ReadAll(res.Body)
		return fmt.Errorf("FCM send failed: HTTP %d: %s", res.StatusCode, string(respBody))
	}
	return nil
}

func (s *FcmSender) accessTokenFor(ctx context.Context) (string, error) {
	s.mu.Lock()
	if s.accessToken != "" && time.Now().Before(s.expiresAt.Add(-2*time.Minute)) {
		t := s.accessToken
		s.mu.Unlock()
		return t, nil
	}
	s.mu.Unlock()

	jwt, err := s.signJWT(time.Now())
	if err != nil {
		return "", err
	}
	form := url.Values{}
	form.Set("grant_type", tokenGrant)
	form.Set("assertion", jwt)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.sa.TokenURI,
		strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := s.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	respBody, _ := io.ReadAll(res.Body)
	if res.StatusCode >= 400 {
		return "", fmt.Errorf("FCM token exchange failed: HTTP %d: %s",
			res.StatusCode, string(respBody))
	}
	var token struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(respBody, &token); err != nil {
		return "", fmt.Errorf("parse token response: %w", err)
	}
	if token.AccessToken == "" {
		return "", errors.New("FCM token response missing access_token")
	}
	s.mu.Lock()
	s.accessToken = token.AccessToken
	s.expiresAt = time.Now().Add(time.Duration(token.ExpiresIn) * time.Second)
	s.mu.Unlock()
	return token.AccessToken, nil
}

func (s *FcmSender) signJWT(now time.Time) (string, error) {
	header := map[string]string{"alg": "RS256", "typ": "JWT"}
	claims := map[string]any{
		"iss":   s.sa.ClientEmail,
		"scope": fcmScope,
		"aud":   s.sa.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(jwtLifetime).Unix(),
	}
	hb, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	cb, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	encoded := base64URL(hb) + "." + base64URL(cb)
	digest := sha256.Sum256([]byte(encoded))
	sig, err := rsa.SignPKCS1v15(rand.Reader, s.privateKey, crypto.SHA256, digest[:])
	if err != nil {
		return "", err
	}
	return encoded + "." + base64URL(sig), nil
}

func base64URL(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}
