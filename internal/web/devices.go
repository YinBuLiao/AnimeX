package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// MobileDevice ties a push token to a user.
type MobileDevice struct {
	UserID     string `json:"user_id"`
	FcmToken   string `json:"fcm_token"`
	Platform   string `json:"platform"`
	CreatedAt  int64  `json:"created_at"`
	LastSeenAt int64  `json:"last_seen_at"`
}

type devicesFile struct {
	Devices []MobileDevice `json:"devices"`
}

type deviceStore struct {
	path string
	mu   sync.Mutex
}

func newDeviceStore(path string) *deviceStore {
	return &deviceStore{path: path}
}

func (d *deviceStore) load() (devicesFile, error) {
	data, err := os.ReadFile(d.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return devicesFile{Devices: []MobileDevice{}}, nil
		}
		return devicesFile{}, err
	}
	var f devicesFile
	if err := json.Unmarshal(data, &f); err != nil {
		return devicesFile{Devices: []MobileDevice{}}, nil
	}
	if f.Devices == nil {
		f.Devices = []MobileDevice{}
	}
	return f, nil
}

func (d *deviceStore) save(f devicesFile) error {
	if err := os.MkdirAll(filepath.Dir(d.path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	tmp := d.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, d.path)
}

// register upserts a device by (fcm_token); a token migrating between users
// rebinds to the new owner.
func (d *deviceStore) register(dev MobileDevice) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	f, err := d.load()
	if err != nil {
		return err
	}
	now := time.Now().Unix()
	for i, existing := range f.Devices {
		if existing.FcmToken == dev.FcmToken {
			f.Devices[i].UserID = dev.UserID
			f.Devices[i].Platform = dev.Platform
			f.Devices[i].LastSeenAt = now
			return d.save(f)
		}
	}
	if dev.CreatedAt <= 0 {
		dev.CreatedAt = now
	}
	dev.LastSeenAt = now
	f.Devices = append(f.Devices, dev)
	return d.save(f)
}

func (d *deviceStore) unregister(fcmToken string) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	f, err := d.load()
	if err != nil {
		return err
	}
	kept := f.Devices[:0]
	for _, existing := range f.Devices {
		if existing.FcmToken == fcmToken {
			continue
		}
		kept = append(kept, existing)
	}
	f.Devices = kept
	return d.save(f)
}

// tokensFor returns the FCM tokens registered for a user.
func (d *deviceStore) tokensFor(userID string) ([]MobileDevice, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	f, err := d.load()
	if err != nil {
		return nil, err
	}
	out := make([]MobileDevice, 0)
	for _, dev := range f.Devices {
		if dev.UserID == userID {
			out = append(out, dev)
		}
	}
	return out, nil
}

func (s Server) deviceStore() *deviceStore {
	return newDeviceStore(filepath.Join(filepath.Dir(s.configPath()), "mobile_devices.json"))
}

type deviceRegisterRequest struct {
	FcmToken string `json:"fcm_token"`
	Platform string `json:"platform"`
}

func (s Server) handleDeviceRegister(w http.ResponseWriter, r *http.Request) {
	user, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req deviceRegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.FcmToken = strings.TrimSpace(req.FcmToken)
	req.Platform = strings.TrimSpace(strings.ToLower(req.Platform))
	if req.FcmToken == "" {
		writeError(w, http.StatusBadRequest, errors.New("fcm_token 必填"))
		return
	}
	if req.Platform != "ios" && req.Platform != "android" {
		writeError(w, http.StatusBadRequest, errors.New("platform 必须为 ios 或 android"))
		return
	}
	dev := MobileDevice{
		UserID:   user.Username,
		FcmToken: req.FcmToken,
		Platform: req.Platform,
	}
	if err := s.deviceStore().register(dev); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type deviceUnregisterRequest struct {
	FcmToken string `json:"fcm_token"`
}

func (s Server) handleDeviceUnregister(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.authenticatedUser(r); !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req deviceUnregisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.FcmToken = strings.TrimSpace(req.FcmToken)
	if req.FcmToken == "" {
		writeError(w, http.StatusBadRequest, errors.New("fcm_token 必填"))
		return
	}
	if err := s.deviceStore().unregister(req.FcmToken); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
