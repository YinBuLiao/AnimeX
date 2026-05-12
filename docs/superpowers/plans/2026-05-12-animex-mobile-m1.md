# AnimeX Mobile M1 Implementation Plan — Flutter Shell + Server Connect + Login

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a runnable Flutter app (iOS + Android) that lets the user enter a server URL, optionally accept self-signed certs, test the connection, log in with username/password, and land on a home shell that proves the session works. Backend gets the minimum new endpoints to support this flow.

**Architecture:** Existing Go backend gains `GET /api/health` (anonymous probe) and `POST /api/auth/mobile-login` (returns JSON `{token, ...}` instead of setting a cookie). `authenticatedUser` is extended to read `Authorization: Bearer <token>` in addition to the cookie, so the entire existing protected API surface becomes mobile-callable for free. Mobile is a brand-new Flutter project at `mobile/`, talking to the backend via Dio. Flow: cold start → server-setup page → login page → home shell. Session token persisted in `flutter_secure_storage`.

**Tech Stack:** Go 1.25 (backend), Flutter ≥ 3.27 / Dart ≥ 3.5 (mobile), `dio` 5.7, `flutter_riverpod` 2.5, `go_router` 14.6, `flutter_secure_storage` 9.2, `freezed` 2.5, `json_serializable` 6.8.

**Spec reference:** `docs/superpowers/specs/2026-05-12-animex-mobile-app-design.md` (commits `ed63c62`, `a8b40c1`)

---

## Prerequisites (do once before Task 1)

- Flutter SDK ≥ 3.27 installed (`flutter --version`)
- Xcode + a free Apple ID for iOS device install (Mac only)
- Android Studio + Android SDK or just `cmdline-tools` + ADB
- A running AnimeX backend on the LAN for manual verification at end (you can use `go run ./main.go -addr 0.0.0.0:8080` on dev machine)

---

## Part A — Backend (Go) endpoints

### Task 1: Add `GET /api/health` anonymous probe

**Files:**
- Create: `internal/web/health.go`
- Modify: `internal/web/server.go:152-181` (route registration block)
- Test: `internal/web/health_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/web/health_test.go`:

```go
package web

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleHealthReturnsVersionAndInstalledFlag(t *testing.T) {
	s := Server{Version: "test-v1", Installed: true}

	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rr := httptest.NewRecorder()
	s.handleHealth(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status: got %d want 200; body=%s", rr.Code, rr.Body.String())
	}
	if ct := rr.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("content-type: got %q want application/json...", ct)
	}
	var body struct {
		OK        bool   `json:"ok"`
		Version   string `json:"version"`
		Installed bool   `json:"installed"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if !body.OK || body.Version != "test-v1" || !body.Installed {
		t.Fatalf("body mismatch: %+v", body)
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
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/web/ -run TestHandleHealth -v
```

Expected: FAIL — `s.handleHealth undefined` and likely `Server` has no `Version`/`Installed` fields. That's fine, we'll add them.

- [ ] **Step 3: Inspect the `Server` struct definition**

Read `internal/web/server.go` lines 30-80 to find the `Server` struct. Note what fields exist so the new ones fit the same style.

- [ ] **Step 4: Add `Version` and `Installed` fields to the `Server` struct**

In `internal/web/server.go`, locate the `Server` struct and append two fields (keep style consistent with existing ones):

```go
// Within the Server struct, add at the end of the field list:
Version   string
Installed bool
```

- [ ] **Step 5: Create the handler**

Create `internal/web/health.go`:

```go
package web

import (
	"errors"
	"net/http"
)

func (s Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":        true,
		"version":   s.Version,
		"installed": s.Installed,
	})
}
```

- [ ] **Step 6: Register the route**

In `internal/web/server.go`, find the route registration block (around line 152 onwards) and add this line near the other `/api/...` routes (place it right after the line registering `/api/status`):

```go
mux.HandleFunc("/api/health", s.handleHealth)
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
go test ./internal/web/ -run TestHandleHealth -v
```

Expected: PASS for both `TestHandleHealthReturnsVersionAndInstalledFlag` and `TestHandleHealthRejectsNonGET`.

- [ ] **Step 8: Wire `Version` and `Installed` at startup**

Read `main.go` to find where the `Server` struct is constructed (search for `web.Server{`). Add the two new fields. For `Version`, use a package-level var that defaults to `"dev"` (we'll inject via `-ldflags` later if needed); for `Installed`, use the existing install-status check the code already performs.

Edit `main.go` (search for the line constructing `web.Server{...}`):

```go
// Before this line, add:
const appVersion = "dev"

// Inside the web.Server{...} literal, add these two fields (the install-check
// function may have a different name; match what main.go already uses to detect
// whether the install wizard has completed):
Version:   appVersion,
Installed: installCompleted, // adjust to whatever boolean main.go uses
```

If `main.go` doesn't track `installCompleted` as a bool yet, look at how `handleInstallStatus` decides — it reads from `s.Config()` or similar. Mirror that here. Don't invent a new persistence path.

- [ ] **Step 9: Verify the full build**

```bash
go build ./...
go test ./internal/web/...
```

Expected: both pass.

- [ ] **Step 10: Commit**

```bash
git add internal/web/health.go internal/web/health_test.go internal/web/server.go main.go
git commit -m "feat(api): add anonymous /api/health for mobile probe"
```

---

### Task 2: Accept `Authorization: Bearer <token>` in `authenticatedUser`

**Files:**
- Modify: `internal/web/server.go:2249-2255` (the `authenticatedUser` function)
- Test: `internal/web/auth_bearer_test.go` (new)

- [ ] **Step 1: Write the failing test**

Create `internal/web/auth_bearer_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/web/ -run TestAuthenticatedUser -v
```

Expected: `TestAuthenticatedUserAcceptsBearerToken` FAILS (function only checks cookie). The cookie and bogus-bearer tests pass.

- [ ] **Step 3: Extend `authenticatedUser`**

Edit `internal/web/server.go`. Replace the existing `authenticatedUser` function:

```go
func (s Server) authenticatedUser(r *http.Request) (config.User, bool) {
	if cookie, err := r.Cookie(authCookieName); err == nil {
		if user, ok := s.Sessions.User(cookie.Value); ok {
			return user, true
		}
	}
	if header := r.Header.Get("Authorization"); header != "" {
		const prefix = "Bearer "
		if len(header) > len(prefix) && strings.EqualFold(header[:len(prefix)], prefix) {
			token := strings.TrimSpace(header[len(prefix):])
			if user, ok := s.Sessions.User(token); ok {
				return user, true
			}
		}
	}
	return config.User{}, false
}
```

(Imports already include `strings` and `config`; no new imports needed.)

- [ ] **Step 4: Run the test to verify it passes**

```bash
go test ./internal/web/ -run TestAuthenticatedUser -v
```

Expected: all three PASS.

- [ ] **Step 5: Make sure the rest of the suite still passes**

```bash
go test ./...
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/web/server.go internal/web/auth_bearer_test.go
git commit -m "feat(api): accept Authorization Bearer header for mobile clients"
```

---

### Task 3: Add `POST /api/auth/mobile-login` (returns token in JSON)

**Files:**
- Create: `internal/web/mobile_auth.go`
- Modify: `internal/web/server.go` (route registration block — same one as Task 1)
- Test: `internal/web/mobile_auth_test.go`

- [ ] **Step 1: Write the failing test**

Create `internal/web/mobile_auth_test.go`:

```go
package web

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"bangumi-pikpak/internal/config"
)

type fakeUserLookup struct {
	users map[string]config.User
}

func (f fakeUserLookup) loginUser(ctx interface{}, username, password string) (config.User, bool, error) {
	// not used; we'll inject the real path via the test harness below
	return config.User{}, false, nil
}

func TestHandleMobileLoginReturnsTokenOnSuccess(t *testing.T) {
	// Construct a Server that accepts a known admin via the config-driven path
	cfg := config.Config{AdminUsername: "alice", AdminPassword: "secret"}
	store := NewSessionStore()
	s := Server{Sessions: store, ConfigProvider: func() config.Config { return cfg }}

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
	if _, ok := store.User(resp.Token); !ok {
		t.Fatalf("token not stored in session store")
	}
	// Cookie MUST NOT be set on mobile-login (this is the difference vs /api/auth/login)
	if len(rr.Result().Cookies()) != 0 {
		t.Fatalf("mobile-login set a cookie; should not: %v", rr.Result().Cookies())
	}
}

func TestHandleMobileLoginRejectsBadPassword(t *testing.T) {
	cfg := config.Config{AdminUsername: "alice", AdminPassword: "secret"}
	s := Server{Sessions: NewSessionStore(), ConfigProvider: func() config.Config { return cfg }}

	body, _ := json.Marshal(map[string]string{"username": "alice", "password": "WRONG"})
	req := httptest.NewRequest(http.MethodPost, "/api/auth/mobile-login", bytes.NewReader(body))
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("status: got %d want 401", rr.Code)
	}
}

func TestHandleMobileLoginRejectsNonPOST(t *testing.T) {
	s := Server{}
	req := httptest.NewRequest(http.MethodGet, "/api/auth/mobile-login", nil)
	rr := httptest.NewRecorder()
	s.handleMobileLogin(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status: got %d want 405", rr.Code)
	}
}
```

> **Note on `ConfigProvider`:** Look at `internal/web/server.go` for how Server gets at the current `config.Config` (it might be `s.Config`, `s.runtimeConfig()`, or a callback field). Match the existing pattern instead of introducing a new `ConfigProvider` field. The test above shows the *intent* — adapt the test to the actual mechanism. **Read the existing `s.loginUser` call in `handleAuthLogin` (around line 196 in `server.go`) and reuse the same code path.** If `loginUser` exists, just call it from the new handler — no fake needed.

> **Update the test once you've read the codebase**, replacing the `ConfigProvider` field with whatever `handleAuthLogin` actually uses. The assertions (token returned, no cookie, 401 on bad creds, 405 on wrong method) stay.

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/web/ -run TestHandleMobileLogin -v
```

Expected: FAIL — `handleMobileLogin` undefined.

- [ ] **Step 3: Create the handler**

Create `internal/web/mobile_auth.go`:

```go
package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
)

type mobileLoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s Server) handleMobileLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req mobileLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	user, ok, err := s.loginUser(r.Context(), strings.TrimSpace(req.Username), req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("用户名或密码错误"))
		return
	}
	token, expires, err := s.Sessions.Create(user.Username, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Deliberately do NOT call setSessionCookie — mobile clients use the token directly.
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":         true,
		"token":      token,
		"expires_at": expires.Unix(),
		"username":   user.Username,
		"role":       user.Role,
	})
}
```

- [ ] **Step 4: Register the route**

In `internal/web/server.go`, in the same route registration block, add:

```go
mux.HandleFunc("/api/auth/mobile-login", s.handleMobileLogin)
```

Place it right next to `/api/auth/login`.

- [ ] **Step 5: Run the test to verify it passes**

```bash
go test ./internal/web/ -run TestHandleMobileLogin -v
```

Expected: PASS for all three.

- [ ] **Step 6: Run the whole test suite**

```bash
go test ./...
```

Expected: PASS.

- [ ] **Step 7: Manual smoke**

In one terminal:
```bash
go run ./main.go -addr 127.0.0.1:8080
```

In another:
```bash
curl -s http://127.0.0.1:8080/api/health | jq .
# expect: {"ok":true,"version":"dev","installed":true|false}

curl -s -X POST http://127.0.0.1:8080/api/auth/mobile-login \
  -H 'Content-Type: application/json' \
  -d '{"username":"<your-admin>","password":"<your-password>"}' | jq .
# expect: {"ok":true,"token":"...","expires_at":...,"username":"...","role":"admin"}
```

Save the printed `token` — verify Bearer auth works:
```bash
curl -s http://127.0.0.1:8080/api/auth/me \
  -H "Authorization: Bearer <paste-token-here>" | jq .
# expect: {"ok":true,"username":"...","role":"admin"}
```

- [ ] **Step 8: Commit**

```bash
git add internal/web/mobile_auth.go internal/web/mobile_auth_test.go internal/web/server.go
git commit -m "feat(api): add /api/auth/mobile-login returning JSON token"
```

---

## Part B — Flutter scaffold

### Task 4: Bootstrap the Flutter project under `mobile/`

**Files:**
- Create: `mobile/` (entire project skeleton via `flutter create`)
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/.gitignore` (override Flutter default to keep our additions)
- Modify: project-root `.gitignore` (allow `mobile/` to be tracked)

- [ ] **Step 1: Run `flutter create`**

From the AnimeX repo root:

```bash
flutter create \
  --org com.animex \
  --project-name animex_mobile \
  --platforms=ios,android \
  --description "AnimeX mobile client" \
  mobile
```

Expected: a new `mobile/` directory with `lib/`, `ios/`, `android/`, `test/`, `pubspec.yaml`.

- [ ] **Step 2: Verify the default Flutter app builds**

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
cd ..
```

Expected: pub get succeeds; analyze has 0 issues; the default counter widget test passes.

- [ ] **Step 3: Replace `mobile/pubspec.yaml` with our dependencies**

Overwrite `mobile/pubspec.yaml` with:

```yaml
name: animex_mobile
description: "AnimeX mobile client"
publish_to: "none"
version: 0.1.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  dio: ^5.7.0
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^14.6.0
  flutter_secure_storage: ^9.2.2
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.3
  custom_lint: ^0.6.7
  riverpod_lint: ^2.3.13
  http_mock_adapter: ^0.6.1

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Install deps**

```bash
cd mobile
flutter pub get
cd ..
```

Expected: pub get succeeds. (If it complains about Dart SDK version, bump your Flutter to ≥ 3.27.)

- [ ] **Step 5: Delete the default counter app**

```bash
rm mobile/lib/main.dart
rm mobile/test/widget_test.dart
```

We'll replace these in later tasks.

- [ ] **Step 6: Ensure `mobile/` is tracked by git**

Check the project-root `.gitignore` does not exclude `mobile/`:

```bash
grep -n "mobile" .gitignore || echo "mobile/ not ignored — ok"
```

If a line excludes `mobile/`, remove it.

Inside `mobile/.gitignore` (auto-generated by `flutter create`) keep defaults. Do not commit `build/`, `.dart_tool/`, `.flutter-plugins`, etc. — Flutter's default `.gitignore` handles this.

- [ ] **Step 7: Commit the scaffold**

```bash
git add mobile/ .gitignore
git status   # review what's being added — should NOT include build/, .dart_tool/
git commit -m "chore(mobile): bootstrap Flutter project skeleton"
```

---

### Task 5: Add app theme

**Files:**
- Create: `mobile/lib/app/theme.dart`
- Test: `mobile/test/app/theme_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/app/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/app/theme.dart';

void main() {
  test('animexDarkTheme uses dark brightness and our background color', () {
    final t = animexDarkTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, const Color(0xFF0F1014));
    expect(t.useMaterial3, isTrue);
  });

  test('animexDarkTheme exposes the surfaceContainer card color', () {
    final t = animexDarkTheme();
    expect(t.colorScheme.surfaceContainer, const Color(0xFF1A1B22));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/app/theme_test.dart
```

Expected: FAIL — `theme.dart` not found.

- [ ] **Step 3: Create the theme**

Create `mobile/lib/app/theme.dart`:

```dart
import 'package:flutter/material.dart';

const _bg = Color(0xFF0F1014);
const _card = Color(0xFF1A1B22);
const _accent = Color(0xFFFF6B3D); // saturated orange-red

ThemeData animexDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: _bg,
    surfaceContainer: _card,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: _bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(color: _card, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2B33)),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/app/theme_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/app/theme.dart mobile/test/app/theme_test.dart
git commit -m "feat(mobile): add AnimeX dark theme"
```

---

### Task 6: Server config storage (URL + self-signed cert flag)

**Files:**
- Create: `mobile/lib/core/config/server_config.dart`
- Test: `mobile/test/core/config/server_config_test.dart`

We're hiding `flutter_secure_storage` behind an abstract `ServerConfigStore` so tests can use an in-memory implementation.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/config/server_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/core/config/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('isComplete is true only with a non-empty URL', () {
      expect(const ServerConfig().isComplete, isFalse);
      expect(const ServerConfig(baseUrl: 'https://x:8080').isComplete, isTrue);
    });

    test('normalizes by stripping trailing slashes', () {
      final c = ServerConfig.normalize('https://example.com:8080///');
      expect(c.baseUrl, 'https://example.com:8080');
    });

    test('rejects URLs without http/https scheme', () {
      expect(() => ServerConfig.normalize('example.com'), throwsFormatException);
      expect(() => ServerConfig.normalize('ftp://example.com'), throwsFormatException);
    });

    test('normalize preserves allowSelfSigned flag', () {
      final c = ServerConfig.normalize('https://x/', allowSelfSigned: true);
      expect(c.allowSelfSigned, isTrue);
    });
  });

  group('InMemoryServerConfigStore', () {
    test('reads back what was written', () async {
      final store = InMemoryServerConfigStore();
      expect(await store.load(), const ServerConfig());

      await store.save(const ServerConfig(baseUrl: 'https://x:8080', allowSelfSigned: true));
      final c = await store.load();
      expect(c.baseUrl, 'https://x:8080');
      expect(c.allowSelfSigned, isTrue);
    });

    test('clear empties the store', () async {
      final store = InMemoryServerConfigStore();
      await store.save(const ServerConfig(baseUrl: 'https://x'));
      await store.clear();
      expect((await store.load()).isComplete, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/core/config/server_config_test.dart
```

Expected: FAIL — file not found.

- [ ] **Step 3: Create the implementation**

Create `mobile/lib/core/config/server_config.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerConfig {
  final String baseUrl;
  final bool allowSelfSigned;

  const ServerConfig({this.baseUrl = '', this.allowSelfSigned = false});

  bool get isComplete => baseUrl.isNotEmpty;

  static ServerConfig normalize(String raw, {bool allowSelfSigned = false}) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw const FormatException('URL must start with http:// or https://');
    }
    var url = trimmed;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return ServerConfig(baseUrl: url, allowSelfSigned: allowSelfSigned);
  }
}

abstract class ServerConfigStore {
  Future<ServerConfig> load();
  Future<void> save(ServerConfig config);
  Future<void> clear();
}

class SecureServerConfigStore implements ServerConfigStore {
  static const _kBaseUrl = 'server_url';
  static const _kAllowSelfSigned = 'allow_self_signed_cert';

  final FlutterSecureStorage _storage;
  SecureServerConfigStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<ServerConfig> load() async {
    final url = await _storage.read(key: _kBaseUrl) ?? '';
    final flag = await _storage.read(key: _kAllowSelfSigned);
    return ServerConfig(baseUrl: url, allowSelfSigned: flag == '1');
  }

  @override
  Future<void> save(ServerConfig c) async {
    await _storage.write(key: _kBaseUrl, value: c.baseUrl);
    await _storage.write(key: _kAllowSelfSigned, value: c.allowSelfSigned ? '1' : '0');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kAllowSelfSigned);
  }
}

class InMemoryServerConfigStore implements ServerConfigStore {
  ServerConfig _current = const ServerConfig();
  @override
  Future<ServerConfig> load() async => _current;
  @override
  Future<void> save(ServerConfig c) async {
    _current = c;
  }
  @override
  Future<void> clear() async {
    _current = const ServerConfig();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/core/config/server_config_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/config/ mobile/test/core/config/
git commit -m "feat(mobile): server config storage (URL + self-signed flag)"
```

---

### Task 7: Session token storage

**Files:**
- Create: `mobile/lib/core/auth/session_store.dart`
- Test: `mobile/test/core/auth/session_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/auth/session_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/core/auth/session_store.dart';

void main() {
  test('InMemorySessionStore round-trips a session', () async {
    final s = InMemorySessionStore();
    expect(await s.load(), isNull);

    await s.save(const StoredSession(
      token: 'abc',
      username: 'alice',
      role: 'admin',
      expiresAtSec: 1234567890,
    ));
    final got = await s.load();
    expect(got?.token, 'abc');
    expect(got?.username, 'alice');
    expect(got?.role, 'admin');
    expect(got?.expiresAtSec, 1234567890);
  });

  test('clear removes the session', () async {
    final s = InMemorySessionStore();
    await s.save(const StoredSession(
      token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    await s.clear();
    expect(await s.load(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/core/auth/session_store_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create the implementation**

Create `mobile/lib/core/auth/session_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  final String token;
  final String username;
  final String role;
  final int expiresAtSec;

  const StoredSession({
    required this.token,
    required this.username,
    required this.role,
    required this.expiresAtSec,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'role': role,
        'expires_at': expiresAtSec,
      };

  factory StoredSession.fromJson(Map<String, dynamic> j) => StoredSession(
        token: j['token'] as String,
        username: j['username'] as String,
        role: j['role'] as String,
        expiresAtSec: (j['expires_at'] as num).toInt(),
      );
}

abstract class SessionStore {
  Future<StoredSession?> load();
  Future<void> save(StoredSession s);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'session';
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<StoredSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(StoredSession s) =>
      _storage.write(key: _key, value: jsonEncode(s.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemorySessionStore implements SessionStore {
  StoredSession? _current;
  @override
  Future<StoredSession?> load() async => _current;
  @override
  Future<void> save(StoredSession s) async => _current = s;
  @override
  Future<void> clear() async => _current = null;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/core/auth/session_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/auth/ mobile/test/core/auth/
git commit -m "feat(mobile): session token secure storage"
```

---

### Task 8: Dio client factory with cert override + auth interceptor

**Files:**
- Create: `mobile/lib/core/network/dio_client.dart`
- Create: `mobile/lib/core/network/api_exception.dart`
- Test: `mobile/test/core/network/dio_client_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/core/network/dio_client_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';

void main() {
  test('dio is configured with the server base URL', () {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example:8080'),
      sessionStore: InMemorySessionStore(),
    );
    expect(dio.options.baseUrl, 'https://server.example:8080');
  });

  test('auth interceptor injects Bearer header when session exists', () async {
    final sessions = InMemorySessionStore();
    await sessions.save(const StoredSession(
        token: 'my-token', username: 'a', role: 'user', expiresAtSec: 0));
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: sessions,
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/auth/me', (server) {
      server.reply(200, {'ok': true, 'username': 'a', 'role': 'user'});
    });

    final resp = await dio.get('/api/auth/me');
    expect(resp.statusCode, 200);

    // Verify the header was set by inspecting the request the adapter captured
    final lastRequest = adapter.history.last;
    expect(lastRequest.request.headers['Authorization'], 'Bearer my-token');
  });

  test('auth interceptor omits Bearer header when no session', () async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/health', (s) => s.reply(200, {'ok': true}));
    await dio.get('/api/health');
    expect(adapter.history.last.request.headers.containsKey('Authorization'), isFalse);
  });

  test('401 response is mapped to ApiException with isUnauthorized=true', () async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/auth/me', (s) => s.reply(401, {'ok': false, 'error': 'nope'}));
    try {
      await dio.get('/api/auth/me');
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 401);
      expect(e.isUnauthorized, isTrue);
    }
  });
}
```

> **Note:** `http_mock_adapter` exposes `adapter.history` as a list of recorded requests in v0.6.x. If the API differs in your installed version, check `flutter pub deps` and adapt — same intent: prove the header was set.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/core/network/dio_client_test.dart
```

Expected: FAIL — files not present.

- [ ] **Step 3: Create `api_exception.dart`**

Create `mobile/lib/core/network/api_exception.dart`:

```dart
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? cause;

  const ApiException({this.statusCode, required this.message, this.cause});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'ApiException(status=$statusCode, msg=$message)';
}
```

- [ ] **Step 4: Create `dio_client.dart`**

Create `mobile/lib/core/network/dio_client.dart`:

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';

Dio buildDio({
  required ServerConfig config,
  required SessionStore sessionStore,
}) {
  final dio = Dio(BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
    // Surface non-2xx as DioException so our interceptor can convert it.
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ));

  // Self-signed cert override
  if (config.allowSelfSigned) {
    final adapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    dio.httpClientAdapter = adapter;
  }

  dio.interceptors.add(_AuthInterceptor(sessionStore));
  dio.interceptors.add(_ErrorMappingInterceptor());

  return dio;
}

class _AuthInterceptor extends Interceptor {
  final SessionStore _sessions;
  _AuthInterceptor(this._sessions);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final session = await _sessions.load();
    if (session != null && session.token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer ${session.token}';
    }
    handler.next(options);
  }
}

class _ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final msgFromBody = _extractMessage(err.response?.data);
    final msg = msgFromBody ?? err.message ?? 'network error';
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: ApiException(statusCode: status, message: msg, cause: err),
        message: msg,
      ),
    );
  }

  String? _extractMessage(Object? body) {
    if (body is Map && body['error'] is String) {
      return body['error'] as String;
    }
    return null;
  }
}

extension DioErrorUnwrap on DioException {
  ApiException toApi() {
    final e = error;
    if (e is ApiException) return e;
    return ApiException(
      statusCode: response?.statusCode,
      message: message ?? 'network error',
      cause: this,
    );
  }
}
```

> **Repositories will catch `DioException` and call `.toApi()` to surface `ApiException`** — see Tasks 10 and 11.

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/core/network/dio_client_test.dart
```

Expected: PASS for the first three tests; the 401 test currently FAILS because `dio` is throwing `DioException`, not `ApiException`. **Update the test's catch clause:**

```dart
} on DioException catch (e) {
  final api = e.toApi();
  expect(api.statusCode, 401);
  expect(api.isUnauthorized, isTrue);
}
```

Re-import the extension at the top of the test:

```dart
import 'package:animex_mobile/core/network/dio_client.dart' show buildDio, DioErrorUnwrap;
```

Run again:

```bash
cd mobile && flutter test test/core/network/dio_client_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/core/network/ mobile/test/core/network/
git commit -m "feat(mobile): Dio client with cert override + auth interceptor"
```

---

### Task 9: DTOs (HealthInfo, AppUser, LoginResponse)

We're hand-writing serialization (no codegen needed for these few simple types — keeps the M1 cycle short). `freezed` will be introduced in M2 when there are dozens of types.

**Files:**
- Create: `mobile/lib/data/dtos/health_info.dart`
- Create: `mobile/lib/data/dtos/app_user.dart`
- Create: `mobile/lib/data/dtos/login_response.dart`
- Test: `mobile/test/data/dtos/dtos_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/data/dtos/dtos_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:animex_mobile/data/dtos/app_user.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';
import 'package:animex_mobile/data/dtos/login_response.dart';

void main() {
  test('HealthInfo.fromJson parses backend payload', () {
    final h = HealthInfo.fromJson({
      'ok': true,
      'version': 'v0.2.0',
      'installed': true,
    });
    expect(h.version, 'v0.2.0');
    expect(h.installed, isTrue);
  });

  test('AppUser.fromJson parses /api/auth/me payload', () {
    final u = AppUser.fromJson({'ok': true, 'username': 'alice', 'role': 'admin'});
    expect(u.username, 'alice');
    expect(u.role, 'admin');
    expect(u.isAdmin, isTrue);
  });

  test('LoginResponse.fromJson parses mobile-login payload', () {
    final r = LoginResponse.fromJson({
      'ok': true,
      'token': 'tok',
      'expires_at': 1700000000,
      'username': 'bob',
      'role': 'user',
    });
    expect(r.token, 'tok');
    expect(r.expiresAtSec, 1700000000);
    expect(r.user.username, 'bob');
    expect(r.user.role, 'user');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/dtos/dtos_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create `health_info.dart`**

```dart
class HealthInfo {
  final String version;
  final bool installed;
  const HealthInfo({required this.version, required this.installed});

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        version: (j['version'] as String?) ?? '',
        installed: (j['installed'] as bool?) ?? false,
      );
}
```

- [ ] **Step 4: Create `app_user.dart`**

```dart
class AppUser {
  final String username;
  final String role;
  const AppUser({required this.username, required this.role});

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        username: (j['username'] as String?) ?? '',
        role: (j['role'] as String?) ?? '',
      );
}
```

- [ ] **Step 5: Create `login_response.dart`**

```dart
import 'package:animex_mobile/data/dtos/app_user.dart';

class LoginResponse {
  final String token;
  final int expiresAtSec;
  final AppUser user;

  const LoginResponse({
    required this.token,
    required this.expiresAtSec,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> j) => LoginResponse(
        token: (j['token'] as String?) ?? '',
        expiresAtSec: (j['expires_at'] as num?)?.toInt() ?? 0,
        user: AppUser.fromJson(j),
      );
}
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/dtos/dtos_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/data/dtos/ mobile/test/data/dtos/
git commit -m "feat(mobile): DTOs for health/user/login"
```

---

### Task 10: SystemRepository (`health`)

**Files:**
- Create: `mobile/lib/data/repositories/system_repository.dart`
- Test: `mobile/test/data/repositories/system_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/data/repositories/system_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

void main() {
  Dio newDio() => buildDio(
        config: const ServerConfig(baseUrl: 'https://server.example'),
        sessionStore: InMemorySessionStore(),
      );

  test('health() returns parsed HealthInfo on 200', () async {
    final dio = newDio();
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {'ok': true, 'version': 'v0.2', 'installed': true}),
    );
    final repo = SystemRepository(dio);
    final h = await repo.health();
    expect(h.version, 'v0.2');
    expect(h.installed, isTrue);
  });

  test('health() throws ApiException on network failure', () async {
    final dio = newDio();
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.throws(0, DioException(requestOptions: RequestOptions())),
    );
    final repo = SystemRepository(dio);
    await expectLater(repo.health(), throwsA(isA<ApiException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/repositories/system_repository_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create the implementation**

Create `mobile/lib/data/repositories/system_repository.dart`:

```dart
import 'package:dio/dio.dart';

import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';

class SystemRepository {
  final Dio _dio;
  SystemRepository(this._dio);

  Future<HealthInfo> health() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/health');
      return HealthInfo.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/repositories/system_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/repositories/system_repository.dart mobile/test/data/repositories/system_repository_test.dart
git commit -m "feat(mobile): SystemRepository.health()"
```

---

### Task 11: AuthRepository (`login`, `me`, `logout`)

**Files:**
- Create: `mobile/lib/data/repositories/auth_repository.dart`
- Test: `mobile/test/data/repositories/auth_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/data/repositories/auth_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/auth_repository.dart';

void main() {
  late InMemorySessionStore sessions;
  late Dio dio;

  setUp(() {
    sessions = InMemorySessionStore();
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: sessions,
    );
  });

  test('login() persists session and returns user on 200', () async {
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(200, {
        'ok': true,
        'token': 'tok-1',
        'expires_at': 1700000000,
        'username': 'alice',
        'role': 'admin',
      }),
      data: {'username': 'alice', 'password': 'secret'},
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);

    final user = await repo.login('alice', 'secret');
    expect(user.username, 'alice');
    expect(user.role, 'admin');

    final stored = await sessions.load();
    expect(stored?.token, 'tok-1');
    expect(stored?.username, 'alice');
  });

  test('login() throws ApiException on 401', () async {
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(401, {'ok': false, 'error': 'bad creds'}),
      data: {'username': 'a', 'password': 'b'},
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await expectLater(repo.login('a', 'b'), throwsA(isA<ApiException>()));
    expect(await sessions.load(), isNull);
  });

  test('me() returns the current user', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onGet(
      '/api/auth/me',
      (s) => s.reply(200, {'ok': true, 'username': 'alice', 'role': 'admin'}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    final u = await repo.me();
    expect(u.username, 'alice');
  });

  test('logout() clears the session', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onPost(
      '/api/auth/logout',
      (s) => s.reply(200, {'ok': true}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await repo.logout();
    expect(await sessions.load(), isNull);
  });

  test('logout() still clears the session if server returns error', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onPost(
      '/api/auth/logout',
      (s) => s.reply(500, {'error': 'boom'}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await repo.logout(); // should not throw
    expect(await sessions.load(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/data/repositories/auth_repository_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create the implementation**

Create `mobile/lib/data/repositories/auth_repository.dart`:

```dart
import 'package:dio/dio.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/app_user.dart';
import 'package:animex_mobile/data/dtos/login_response.dart';

class AuthRepository {
  final Dio _dio;
  final SessionStore _sessions;
  AuthRepository({required Dio dio, required SessionStore sessions})
      : _dio = dio,
        _sessions = sessions;

  Future<AppUser> login(String username, String password) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/api/auth/mobile-login',
        data: {'username': username, 'password': password},
      );
      final parsed = LoginResponse.fromJson(resp.data ?? const {});
      await _sessions.save(StoredSession(
        token: parsed.token,
        username: parsed.user.username,
        role: parsed.user.role,
        expiresAtSec: parsed.expiresAtSec,
      ));
      return parsed.user;
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<AppUser> me() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/auth/me');
      return AppUser.fromJson(resp.data ?? const {});
    } on DioException catch (e) {
      throw e.toApi();
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {
      // best-effort; clear local state regardless
    }
    await _sessions.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/data/repositories/auth_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/repositories/auth_repository.dart mobile/test/data/repositories/auth_repository_test.dart
git commit -m "feat(mobile): AuthRepository (login/me/logout)"
```

---

### Task 12: Riverpod providers — wire stores, dio, and repositories

**Files:**
- Create: `mobile/lib/app/providers.dart`

These are simple `Provider`s, no test (they just wire concrete instances). A real Riverpod test would override them in widget tests, which we do in Tasks 13–14.

- [ ] **Step 1: Create the file**

Create `mobile/lib/app/providers.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/auth_repository.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

final serverConfigStoreProvider = Provider<ServerConfigStore>((_) => SecureServerConfigStore());
final sessionStoreProvider = Provider<SessionStore>((_) => SecureSessionStore());

/// Async-loaded current ServerConfig (refreshable when user changes server).
final serverConfigProvider = FutureProvider<ServerConfig>((ref) async {
  final store = ref.watch(serverConfigStoreProvider);
  return store.load();
});

/// Dio bound to the current ServerConfig + SessionStore.
final dioProvider = FutureProvider<Dio>((ref) async {
  final config = await ref.watch(serverConfigProvider.future);
  final sessions = ref.watch(sessionStoreProvider);
  return buildDio(config: config, sessionStore: sessions);
});

final systemRepositoryProvider = FutureProvider<SystemRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return SystemRepository(dio);
});

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  final sessions = ref.watch(sessionStoreProvider);
  return AuthRepository(dio: dio, sessions: sessions);
});

/// Cached "is the user logged in" check — used by router redirect.
final currentSessionProvider = FutureProvider<StoredSession?>((ref) async {
  final sessions = ref.watch(sessionStoreProvider);
  return sessions.load();
});
```

- [ ] **Step 2: Verify it compiles**

```bash
cd mobile && flutter analyze
```

Expected: 0 issues.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/app/providers.dart
git commit -m "feat(mobile): Riverpod providers wiring config/dio/repositories"
```

---

### Task 13: Server setup page

**Files:**
- Create: `mobile/lib/features/server_setup/server_setup_page.dart`
- Test: `mobile/test/features/server_setup/server_setup_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `mobile/test/features/server_setup/server_setup_page_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';

Widget _harness({
  required ServerConfigStore configStore,
  required Dio dio,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      serverConfigStoreProvider.overrideWithValue(configStore),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      // For "test connection" we override dioProvider to return our mock dio.
      dioProvider.overrideWith((_) async => dio),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows URL input and self-signed checkbox', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    await tester.pumpWidget(_harness(
      configStore: InMemoryServerConfigStore(),
      dio: dio,
      child: const ServerSetupPage(),
    ));
    expect(find.widgetWithText(TextField, '服务器地址'), findsOneWidget);
    expect(find.text('忽略 HTTPS 证书错误'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '测试连接'), findsOneWidget);
  });

  testWidgets('rejects invalid URL before calling network', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    await tester.pumpWidget(_harness(
      configStore: InMemoryServerConfigStore(),
      dio: dio,
      child: const ServerSetupPage(),
    ));

    await tester.enterText(find.byType(TextField).first, 'not-a-url');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pump();
    expect(find.textContaining('http://'), findsWidgets);
  });

  testWidgets('successful health probe saves config and shows success', (tester) async {
    final configStore = InMemoryServerConfigStore();
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {'ok': true, 'version': 'v0.2', 'installed': true}),
    );

    await tester.pumpWidget(_harness(
      configStore: configStore,
      dio: dio,
      child: const ServerSetupPage(),
    ));
    await tester.enterText(find.byType(TextField).first, 'https://server.example');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('v0.2'), findsOneWidget);
    final saved = await configStore.load();
    expect(saved.baseUrl, 'https://server.example');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/server_setup/server_setup_page_test.dart
```

Expected: FAIL — page doesn't exist.

- [ ] **Step 3: Create the page**

Create `mobile/lib/features/server_setup/server_setup_page.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _urlController = TextEditingController();
  bool _allowSelfSigned = false;
  bool _busy = false;
  String? _error;
  HealthInfo? _lastHealth;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _error = null;
      _lastHealth = null;
      _busy = true;
    });
    try {
      final config = ServerConfig.normalize(
        _urlController.text,
        allowSelfSigned: _allowSelfSigned,
      );
      // Build a one-shot dio with the entered config so the probe doesn't
      // depend on what's already stored.
      final dio = buildDio(
        config: config,
        sessionStore: ref.read(sessionStoreProvider),
      );
      final health = await SystemRepository(dio).health();
      // Persist on success
      await ref.read(serverConfigStoreProvider).save(config);
      ref.invalidate(serverConfigProvider);
      if (!mounted) return;
      setState(() {
        _lastHealth = health;
      });
    } on FormatException catch (e) {
      setState(() => _error = '${e.message}（请填写 http:// 或 https:// 开头的地址）');
    } on ApiException catch (e) {
      setState(() => _error = '连接失败: ${e.message}');
    } catch (e) {
      setState(() => _error = '连接失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _proceedToLogin() => context.go('/login');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AnimeX')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('服务器地址', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://anime.example.com:8080',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _allowSelfSigned,
                    onChanged: (v) => setState(() => _allowSelfSigned = v ?? false),
                  ),
                  const Expanded(child: Text('忽略 HTTPS 证书错误')),
                ],
              ),
              if (_allowSelfSigned)
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 8),
                  child: Text(
                    '仅在你完全信任此服务器（如自宅自签证书）时启用。',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _testConnection,
                child: _busy
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
              const SizedBox(height: 12),
              if (_lastHealth != null) ...[
                Text('连接成功：版本 ${_lastHealth!.version}'),
                const SizedBox(height: 8),
                if (!_lastHealth!.installed)
                  const Text(
                    '⚠️ 服务器尚未完成安装向导，请先在 Web 端完成安装。',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _lastHealth!.installed ? _proceedToLogin : null,
                  child: const Text('下一步：登录'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/server_setup/server_setup_page_test.dart
```

Expected: PASS for tests 1 and 2. Test 3 may fail because `_testConnection` builds its own Dio (bypassing the override). **Fix:** in test 3, accept that we cannot easily mock the inline `buildDio` — instead, override the `dioProvider` is not enough. Change the production code to use a small factory we can override:

In `mobile/lib/app/providers.dart`, add:

```dart
typedef DioBuilder = Dio Function({required ServerConfig config, required SessionStore sessionStore});

final dioBuilderProvider = Provider<DioBuilder>((_) => buildDio);
```

In `server_setup_page.dart`, replace the inline `final dio = buildDio(...)` with:

```dart
final builder = ref.read(dioBuilderProvider);
final dio = builder(config: config, sessionStore: ref.read(sessionStoreProvider));
```

And in the test 3 harness, add an override:

```dart
dioBuilderProvider.overrideWithValue(
  ({required ServerConfig config, required SessionStore sessionStore}) => dio,
),
```

Re-run:

```bash
cd mobile && flutter test test/features/server_setup/server_setup_page_test.dart
```

Expected: all three PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/app/providers.dart mobile/lib/features/server_setup/ mobile/test/features/server_setup/
git commit -m "feat(mobile): server setup page with health probe"
```

---

### Task 14: Login page

**Files:**
- Create: `mobile/lib/features/auth/login_page.dart`
- Test: `mobile/test/features/auth/login_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `mobile/test/features/auth/login_page_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/features/auth/login_page.dart';

Widget _harness({
  required ServerConfigStore configStore,
  required SessionStore sessions,
  required Dio dio,
}) {
  return ProviderScope(
    overrides: [
      serverConfigStoreProvider.overrideWithValue(configStore),
      sessionStoreProvider.overrideWithValue(sessions),
      dioProvider.overrideWith((_) async => dio),
    ],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  testWidgets('shows username + password fields + login button', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://x'));
    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: InMemorySessionStore(),
      dio: dio,
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '用户名'), findsOneWidget);
    expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });

  testWidgets('successful login persists session', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(200, {
        'ok': true, 'token': 'tok-X', 'expires_at': 1700000000,
        'username': 'alice', 'role': 'admin',
      }),
      data: {'username': 'alice', 'password': 'secret'},
    );
    final sessions = InMemorySessionStore();
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://server.example'));

    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: sessions,
      dio: dio,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    final saved = await sessions.load();
    expect(saved?.token, 'tok-X');
  });

  testWidgets('401 shows error message', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(401, {'ok': false, 'error': '用户名或密码错误'}),
      data: {'username': 'alice', 'password': 'WRONG'},
    );
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://server.example'));

    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: InMemorySessionStore(),
      dio: dio,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'WRONG');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户名或密码错误'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/auth/login_page_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create the page**

Create `mobile/lib/features/auth/login_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.login(_userController.text.trim(), _passController.text);
      ref.invalidate(currentSessionProvider);
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(serverConfigProvider);
    final serverLabel = config.maybeWhen(
      data: (c) => c.baseUrl,
      orElse: () => '',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: [
          if (serverLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(serverLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _userController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await ref.read(serverConfigStoreProvider).clear();
                  ref.invalidate(serverConfigProvider);
                  if (mounted) context.go('/setup');
                },
                child: const Text('更换服务器'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/auth/login_page_test.dart
```

Expected: PASS for all three.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/auth/ mobile/test/features/auth/
git commit -m "feat(mobile): login page"
```

---

### Task 15: Home shell page

This is a minimal placeholder — full home content lands in M2.

**Files:**
- Create: `mobile/lib/features/home/home_page.dart`
- Test: `mobile/test/features/home/home_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `mobile/test/features/home/home_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/features/home/home_page.dart';

void main() {
  testWidgets('home shows the logged-in username', (tester) async {
    final sessions = InMemorySessionStore();
    await sessions.save(const StoredSession(
        token: 'tok', username: 'alice', role: 'admin', expiresAtSec: 0));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(sessions),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('alice'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '退出登录'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/home/home_page_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create the page**

Create `mobile/lib/features/home/home_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AnimeX')),
      body: Center(
        child: session.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('错误：$e'),
          data: (s) {
            if (s == null) {
              return const Text('未登录');
            }
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('欢迎，${s.username}', style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text('角色：${s.role}'),
                const SizedBox(height: 32),
                const Text('M1 完成：服务器连接 + 登录可用'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    final repo = await ref.read(authRepositoryProvider.future);
                    await repo.logout();
                    ref.invalidate(currentSessionProvider);
                    if (context.mounted) context.go('/login');
                  },
                  child: const Text('退出登录'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/home/home_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home/ mobile/test/features/home/
git commit -m "feat(mobile): home shell page"
```

---

### Task 16: Router with cold-start redirect + main.dart

**Files:**
- Create: `mobile/lib/app/router.dart`
- Create: `mobile/lib/main.dart`

This is the integration point. We rely on the smaller widget tests already covering the pages; for the router itself we add a couple of redirect-logic tests.

- [ ] **Step 1: Write the failing redirect test**

Create `mobile/test/app/router_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';

void main() {
  group('decideStartRoute', () {
    test('routes to /setup when no server URL configured', () {
      final r = decideStartRoute(
        config: const ServerConfig(),
        session: null,
      );
      expect(r, '/setup');
    });

    test('routes to /login when server configured but no session', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: null,
      );
      expect(r, '/login');
    });

    test('routes to / (home) when both server and session present', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: 't', username: 'u', role: 'user', expiresAtSec: 0),
      );
      expect(r, '/');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/app/router_test.dart
```

Expected: FAIL — `router.dart` doesn't exist.

- [ ] **Step 3: Create `router.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/features/auth/login_page.dart';
import 'package:animex_mobile/features/home/home_page.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';

String decideStartRoute({
  required ServerConfig config,
  required StoredSession? session,
}) {
  if (!config.isComplete) return '/setup';
  if (session == null || session.token.isEmpty) return '/login';
  return '/';
}

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final configAsync = ref.read(serverConfigProvider);
      final sessionAsync = ref.read(currentSessionProvider);
      final config = configAsync.asData?.value;
      final session = sessionAsync.asData?.value;
      // While initial data still loading, stay where we are.
      if (config == null || sessionAsync.isLoading) return null;

      final desired = decideStartRoute(config: config, session: session);
      final loc = state.matchedLocation;

      // If we're already at the desired route, no redirect.
      if (loc == desired) return null;
      // Allow free movement between login <-> setup once both load.
      if (loc == '/setup' && desired == '/login') return null;
      return desired;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const ServerSetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
    ],
  );
}

final routerProvider = Provider<GoRouter>(buildRouter);
```

- [ ] **Step 4: Run the redirect test to verify it passes**

```bash
cd mobile && flutter test test/app/router_test.dart
```

Expected: PASS.

- [ ] **Step 5: Create `main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/app/theme.dart';

void main() {
  runApp(const ProviderScope(child: AnimeXApp()));
}

class AnimeXApp extends ConsumerWidget {
  const AnimeXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'AnimeX',
      theme: animexDarkTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

- [ ] **Step 6: Full test suite + analyze**

```bash
cd mobile
flutter analyze
flutter test
cd ..
```

Expected: 0 analyzer issues; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/app/router.dart mobile/lib/main.dart mobile/test/app/router_test.dart
git commit -m "feat(mobile): router with cold-start redirect + main entry"
```

---

### Task 17: Manual end-to-end verification on a real device

**Files:** none (verification only).

- [ ] **Step 1: Start backend on dev machine**

```bash
go run ./main.go -addr 0.0.0.0:8080
```

Note the dev machine's LAN IP (e.g., `192.168.1.50`).

- [ ] **Step 2: Run the APP on Android device**

```bash
cd mobile
flutter run -d <android-device-id>
```

(`flutter devices` to list IDs.)

- [ ] **Step 3: Verify the cold-start flow**

On first launch:
- See "服务器地址" page
- Enter `http://192.168.1.50:8080` (or `https://...` if you have certs)
- Tap 测试连接 → see "连接成功：版本 dev"
- Tap 下一步：登录 → on login page, see server URL in top-right
- Enter admin user + password → land on home shell showing "欢迎，<username>"

- [ ] **Step 4: Kill and relaunch — verify auto-resume**

Quit the app fully, relaunch. Should land directly on home (no re-login).

- [ ] **Step 5: Tap 退出登录 → verify**

Tap "退出登录" — should return to login page (server URL retained).

- [ ] **Step 6: From login page, tap 更换服务器 → verify**

Should return to server-setup page with cleared URL.

- [ ] **Step 7: Repeat on iOS**

```bash
cd mobile
flutter run -d <ios-device-id>
```

Note: first iOS run on a real device requires opening `mobile/ios/Runner.xcworkspace` in Xcode and setting a Development Team (free Apple ID is enough). Once set, `flutter run` works.

- [ ] **Step 8: Document any issues found**

If anything fails, fix in-place and re-run the affected tests. Do not commit broken behavior.

- [ ] **Step 9: Final commit (only if something changed during manual verification)**

```bash
git add <whatever changed>
git commit -m "fix(mobile): <issue found during manual verification>"
```

If nothing changed, this step is a no-op.

---

## Definition of Done for M1

- [ ] `go test ./...` green
- [ ] `cd mobile && flutter analyze` returns 0 issues
- [ ] `cd mobile && flutter test` green
- [ ] On a real Android device: full cold-start → login → home flow works
- [ ] On a real iOS device: same
- [ ] Quitting and relaunching auto-resumes session
- [ ] "退出登录" returns to login page; session cleared on disk
- [ ] "更换服务器" clears URL and returns to setup page
- [ ] Backend log shows `Authorization: Bearer ...` arriving on `/api/auth/me` from the device

---

## Out of Scope for M1 (deferred to later milestones)

- Browsing pages (Home content, Discover, Schedule, Search) — M2
- Bangumi/番剧 detail page — M2
- Player and playback — M3
- Library — M4
- Downloads — M4
- Cast/AirPlay/DLNA — M5
- Push notifications — M6
- Admin pages — M7
- Production code-signing pipelines — M8

---

## Self-Review Notes

**Spec coverage** (against `docs/superpowers/specs/2026-05-12-animex-mobile-app-design.md` §5.0 and §10 M1):

| Spec requirement | Covered by |
|---|---|
| 服务器连接页 | Task 13 |
| Server URL + `flutter_secure_storage` | Task 6 + 13 |
| 忽略证书错误开关 | Task 6 (storage) + Task 8 (Dio cert override) + Task 13 (UI) |
| 测试连接 (`/api/health`) | Task 1 (backend) + Task 10 (repo) + Task 13 (UI) |
| 登录页 + URL 显示在右上角 | Task 14 |
| `/api/auth/mobile-login` | Task 3 (backend) + Task 11 (repo) + Task 14 (UI) |
| Bearer header 改造 | Task 2 (backend) + Task 8 (Dio interceptor) |
| Cold-start redirect (config → setup; no session → login; valid → home) | Task 16 |
| 首页空壳 | Task 15 |
| 主题（深色番剧主题）| Task 5 |
| Flutter 脚手架 + Dio | Task 4 + Task 8 |

No gaps.

**Type consistency check:** `StoredSession` field `expiresAtSec` used in 7, 11, 12 — consistent. `ServerConfig.baseUrl` / `allowSelfSigned` consistent across 6, 8, 13. `AppUser.username` / `role` consistent across 9, 11, 14, 15. `ApiException.message` / `statusCode` consistent across 8, 10, 11.

**Placeholder scan:** None. All steps contain runnable code or exact commands.
