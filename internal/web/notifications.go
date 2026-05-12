package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"sync"
	"time"
)

const notificationsMaxEntries = 500

// Well-known notification kinds.
const (
	NotificationKindNewEpisode      = "new_episode"
	NotificationKindRequestApproved = "request_approved"
	NotificationKindGeneric         = "generic"
)

type Notification struct {
	ID           string `json:"id"`
	Kind         string `json:"kind"`
	Title        string `json:"title"`
	Body         string `json:"body,omitempty"`
	BangumiTitle string `json:"bangumi_title,omitempty"`
	Episode      string `json:"episode,omitempty"`
	CoverURL     string `json:"cover_url,omitempty"`
	FileID       string `json:"file_id,omitempty"`
	CreatedAt    int64  `json:"created_at"`
}

type notificationsFile struct {
	Entries []Notification `json:"entries"`
}

type notificationsStore struct {
	root string
	mu   sync.Mutex
	keys map[string]*sync.Mutex
}

func newNotificationsStore(root string) *notificationsStore {
	return &notificationsStore{root: root, keys: map[string]*sync.Mutex{}}
}

func (n *notificationsStore) lockFor(user string) *sync.Mutex {
	n.mu.Lock()
	defer n.mu.Unlock()
	m, ok := n.keys[user]
	if !ok {
		m = &sync.Mutex{}
		n.keys[user] = m
	}
	return m
}

func (n *notificationsStore) path(user string) string {
	return filepath.Join(n.root, sanitizeUsername(user)+".json")
}

func (n *notificationsStore) load(user string) (notificationsFile, error) {
	data, err := os.ReadFile(n.path(user))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return notificationsFile{Entries: []Notification{}}, nil
		}
		return notificationsFile{}, err
	}
	var f notificationsFile
	if err := json.Unmarshal(data, &f); err != nil {
		return notificationsFile{Entries: []Notification{}}, nil
	}
	if f.Entries == nil {
		f.Entries = []Notification{}
	}
	return f, nil
}

func (n *notificationsStore) save(user string, f notificationsFile) error {
	if err := os.MkdirAll(n.root, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(f, "", "  ")
	if err != nil {
		return err
	}
	tmp := n.path(user) + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, n.path(user))
}

// append prepends a new notification and caps the list.
func (n *notificationsStore) append(user string, entry Notification) (Notification, error) {
	mu := n.lockFor(user)
	mu.Lock()
	defer mu.Unlock()
	f, err := n.load(user)
	if err != nil {
		return Notification{}, err
	}
	if entry.CreatedAt <= 0 {
		entry.CreatedAt = time.Now().Unix()
	}
	if entry.ID == "" {
		entry.ID = strconv.FormatInt(entry.CreatedAt, 10) + "-" + strconv.Itoa(len(f.Entries))
	}
	f.Entries = append(f.Entries, entry)
	sort.Slice(f.Entries, func(i, j int) bool {
		return f.Entries[i].CreatedAt > f.Entries[j].CreatedAt
	})
	if len(f.Entries) > notificationsMaxEntries {
		f.Entries = f.Entries[:notificationsMaxEntries]
	}
	if err := n.save(user, f); err != nil {
		return Notification{}, err
	}
	return entry, nil
}

// list returns notifications newer than `since`, sorted newest-first.
// When since <= 0, all entries are returned.
func (n *notificationsStore) list(user string, since int64) ([]Notification, error) {
	mu := n.lockFor(user)
	mu.Lock()
	defer mu.Unlock()
	f, err := n.load(user)
	if err != nil {
		return nil, err
	}
	sort.Slice(f.Entries, func(i, j int) bool {
		return f.Entries[i].CreatedAt > f.Entries[j].CreatedAt
	})
	if since <= 0 {
		return f.Entries, nil
	}
	out := make([]Notification, 0, len(f.Entries))
	for _, e := range f.Entries {
		if e.CreatedAt > since {
			out = append(out, e)
		}
	}
	return out, nil
}

func (s Server) notificationsRoot() string {
	return filepath.Join(filepath.Dir(s.configPath()), "notifications")
}

func (s Server) notificationsStore() *notificationsStore {
	return newNotificationsStore(s.notificationsRoot())
}

// handleNotifications: GET ?since=<unix_ts> lists notifications for the user.
func (s Server) handleNotifications(w http.ResponseWriter, r *http.Request) {
	user, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var since int64
	if raw := r.URL.Query().Get("since"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, errors.New("since 必须为 unix 时间戳"))
			return
		}
		since = v
	}
	entries, err := s.notificationsStore().list(user.Username, since)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
}
