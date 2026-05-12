package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const historyMaxEntries = 200

type HistoryEntry struct {
	FileID       string `json:"file_id"`
	URL          string `json:"url,omitempty"`
	BangumiTitle string `json:"bangumi_title"`
	Episode      string `json:"episode,omitempty"`
	CoverURL     string `json:"cover_url,omitempty"`
	PositionSec  int    `json:"position_sec"`
	DurationSec  int    `json:"duration_sec"`
	UpdatedAt    int64  `json:"updated_at"`
}

type historyFile struct {
	Entries []HistoryEntry `json:"entries"`
}

type historyStore struct {
	root string
	mu   sync.Mutex
	keys map[string]*sync.Mutex
}

func newHistoryStore(root string) *historyStore {
	return &historyStore{root: root, keys: map[string]*sync.Mutex{}}
}

func (h *historyStore) lockFor(user string) *sync.Mutex {
	h.mu.Lock()
	defer h.mu.Unlock()
	m, ok := h.keys[user]
	if !ok {
		m = &sync.Mutex{}
		h.keys[user] = m
	}
	return m
}

func sanitizeUsername(name string) string {
	out := make([]rune, 0, len(name))
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-' || r == '_':
			out = append(out, r)
		default:
			out = append(out, '_')
		}
	}
	return string(out)
}

func (h *historyStore) path(user string) string {
	return filepath.Join(h.root, sanitizeUsername(user)+".json")
}

func (h *historyStore) load(user string) (historyFile, error) {
	data, err := os.ReadFile(h.path(user))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return historyFile{Entries: []HistoryEntry{}}, nil
		}
		return historyFile{}, err
	}
	var f historyFile
	if err := json.Unmarshal(data, &f); err != nil {
		return historyFile{Entries: []HistoryEntry{}}, nil
	}
	if f.Entries == nil {
		f.Entries = []HistoryEntry{}
	}
	return f, nil
}

func (h *historyStore) save(user string, f historyFile) error {
	if err := os.MkdirAll(h.root, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	tmp := h.path(user) + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, h.path(user))
}

// upsert merges in an entry, capping to historyMaxEntries.
func (h *historyStore) upsert(user string, entry HistoryEntry) ([]HistoryEntry, error) {
	mu := h.lockFor(user)
	mu.Lock()
	defer mu.Unlock()
	f, err := h.load(user)
	if err != nil {
		return nil, err
	}
	if entry.UpdatedAt <= 0 {
		entry.UpdatedAt = time.Now().Unix()
	}
	replaced := false
	for i, e := range f.Entries {
		if e.FileID != "" && e.FileID == entry.FileID {
			f.Entries[i] = entry
			replaced = true
			break
		}
	}
	if !replaced {
		f.Entries = append(f.Entries, entry)
	}
	sort.Slice(f.Entries, func(i, j int) bool {
		return f.Entries[i].UpdatedAt > f.Entries[j].UpdatedAt
	})
	if len(f.Entries) > historyMaxEntries {
		f.Entries = f.Entries[:historyMaxEntries]
	}
	if err := h.save(user, f); err != nil {
		return nil, err
	}
	return f.Entries, nil
}

func (h *historyStore) list(user string) ([]HistoryEntry, error) {
	mu := h.lockFor(user)
	mu.Lock()
	defer mu.Unlock()
	f, err := h.load(user)
	if err != nil {
		return nil, err
	}
	sort.Slice(f.Entries, func(i, j int) bool {
		return f.Entries[i].UpdatedAt > f.Entries[j].UpdatedAt
	})
	return f.Entries, nil
}

func (s Server) historyRoot() string {
	return filepath.Join(filepath.Dir(s.configPath()), "history")
}

func (s Server) historyStore() *historyStore {
	return newHistoryStore(s.historyRoot())
}

// handleHistory: GET lists; PUT/POST upserts; DELETE clears for the user.
func (s Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	user, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	store := s.historyStore()
	switch r.Method {
	case http.MethodGet:
		entries, err := store.list(user.Username)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
	case http.MethodPut, http.MethodPost:
		var entry HistoryEntry
		if err := json.NewDecoder(r.Body).Decode(&entry); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if strings.TrimSpace(entry.FileID) == "" {
			writeError(w, http.StatusBadRequest, errors.New("file_id 必填"))
			return
		}
		entries, err := store.upsert(user.Username, entry)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
	case http.MethodDelete:
		if err := store.clear(user.Username); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	default:
		w.Header().Set("Allow", "GET, PUT, POST, DELETE")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

// clear deletes the per-user history file entirely.
func (h *historyStore) clear(user string) error {
	mu := h.lockFor(user)
	mu.Lock()
	defer mu.Unlock()
	err := os.Remove(h.path(user))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}
