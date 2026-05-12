package web

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
	"unicode"

	"bangumi-pikpak/internal/app"
	"bangumi-pikpak/internal/bangumi"
	"bangumi-pikpak/internal/cache"
	"bangumi-pikpak/internal/config"
	"bangumi-pikpak/internal/mikan"
	"bangumi-pikpak/internal/pikpak"
	"bangumi-pikpak/internal/proxy"
	"bangumi-pikpak/internal/rss"
	"bangumi-pikpak/internal/storage"
	"bangumi-pikpak/internal/store"

	_ "github.com/go-sql-driver/mysql"
)

type PikPakClient interface {
	app.PikPakClient
	DriveClient
}

type Server struct {
	Config       config.Config
	ConfigPath   string
	ConfigDBPath string
	LocalDB      *config.LocalDB
	InstallOnly  bool
	Sessions     *SessionStore
	Runtime      *RuntimeState
	HTTPClient   *http.Client
	Logger       *slog.Logger
	TorrentRoot  string
	StaticDir    string
	PikPak       PikPakClient
	Storage      storage.Provider
	Store        *store.MySQLStore
	Cache        *cache.RedisCache
	Version      string
}

type downloadRequest struct {
	Title        string `json:"title"`
	BangumiTitle string `json:"bangumi_title"`
	EpisodeLabel string `json:"episode_label"`
	CoverURL     string `json:"cover_url"`
	Summary      string `json:"summary"`
	Link         string `json:"link"`
	TorrentURL   string `json:"torrent_url"`
	Magnet       string `json:"magnet"`
}

type searchResponse struct {
	Results      []mikan.SearchResult `json:"results"`
	Query        string               `json:"query,omitempty"`
	MatchedQuery string               `json:"matched_query,omitempty"`
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type userRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Role     string `json:"role"`
}

type registerRequest struct {
	Username   string `json:"username"`
	Password   string `json:"password"`
	InviteCode string `json:"invite_code"`
}

type passwordChangeRequest struct {
	OldPassword     string `json:"old_password"`
	NewPassword     string `json:"new_password"`
	ConfirmPassword string `json:"confirm_password"`
}

type inviteCodeRequest struct {
	Count     int      `json:"count"`
	ExpiresAt string   `json:"expires_at"`
	Codes     []string `json:"codes"`
}

type adminAnimeDeleteRequest struct {
	IDs         []string `json:"ids"`
	Titles      []string `json:"titles"`
	DeleteFiles bool     `json:"delete_files"`
}

type adminEpisodeDeleteRequest struct {
	BangumiID    string `json:"bangumi_id"`
	BangumiTitle string `json:"bangumi_title"`
	EpisodeID    string `json:"episode_id"`
	EpisodeLabel string `json:"episode_label"`
	DeleteFiles  bool   `json:"delete_files"`
}

type adminDownloadRequestAction struct {
	ID     int64  `json:"id"`
	Action string `json:"action"`
}

const librarySnapshotKey = "pikpak_library"
const librarySnapshotTTL = 10 * time.Minute
const externalCacheTTL = 15 * time.Minute

var serverStartedAt = time.Now()

func (s Server) Handler() http.Handler {
	if s.Sessions == nil {
		s.Sessions = NewSessionStore(s.Cache)
	}
	if s.LocalDB == nil {
		if db, err := config.OpenLocalDB(s.configDBPath()); err == nil {
			s.LocalDB = db
			if cfg, ok, err := db.LoadConfig(context.Background()); err == nil && ok {
				s.Config = installConfigWithDefaults(cfg)
			}
		}
	}
	installed := false
	if s.LocalDB != nil {
		installed = s.LocalDB.Installed(context.Background())
	}
	if s.Runtime == nil {
		s.Runtime = NewRuntimeState(s.Config, installed, s.InstallOnly, s.HTTPClient, s.PikPak, s.Storage, s.Store, s.Cache)
	}
	s.Sessions.SetRedis(s.redisCache())
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleIndex)
	mux.HandleFunc("/favicon.ico", s.handleFavicon)
	mux.HandleFunc("/api/auth/login", s.handleAuthLogin)
	mux.HandleFunc("/api/auth/logout", s.handleAuthLogout)
	mux.HandleFunc("/api/auth/me", s.handleAuthMe)
	mux.HandleFunc("/api/auth/register", s.handleAuthRegister)
	mux.HandleFunc("/api/auth/password", s.handleAuthPassword)
	mux.HandleFunc("/api/users", s.handleUsers)
	mux.HandleFunc("/api/admin/overview", s.handleAdminOverview)
	mux.HandleFunc("/api/admin/anime", s.handleAdminAnime)
	mux.HandleFunc("/api/admin/anime/episode", s.handleAdminAnimeEpisode)
	mux.HandleFunc("/api/admin/download-requests", s.handleAdminDownloadRequests)
	mux.HandleFunc("/api/admin/logs", s.handleAdminLogs)
	mux.HandleFunc("/api/admin/monitor", s.handleAdminMonitor)
	mux.HandleFunc("/api/admin/config", s.handleAdminConfig)
	mux.HandleFunc("/api/admin/invite-codes", s.handleAdminInviteCodes)
	mux.HandleFunc("/api/install", s.handleInstall)
	mux.HandleFunc("/api/install/status", s.handleInstallStatus)
	mux.HandleFunc("/api/install/test/mysql", s.handleInstallTestMySQL)
	mux.HandleFunc("/api/install/test/redis", s.handleInstallTestRedis)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/health", s.handleHealth)
	mux.HandleFunc("/api/library", s.handleLibrary)
	mux.HandleFunc("/api/search", s.handleSearch)
	mux.HandleFunc("/api/bangumi/discover", s.handleBangumiDiscover)
	mux.HandleFunc("/api/mikan/schedule", s.handleMikanSchedule)
	mux.HandleFunc("/api/mikan/subscribe", s.handleMikanSubscribe)
	mux.HandleFunc("/api/download", s.handleDownload)
	mux.HandleFunc("/api/download/request", s.handleDownloadRequest)
	mux.HandleFunc("/api/sync", s.handleSync)
	mux.HandleFunc("/api/stream", s.handleStream)
	return loggingMiddleware(s.log(), s.installLockMiddleware(s.authMiddleware(mux)))
}

func (s Server) handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req loginRequest
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
	setSessionCookie(w, token, expires)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": user.Username, "role": user.Role})
}

func (s Server) handleAuthLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	if cookie, err := r.Cookie(authCookieName); err == nil {
		s.Sessions.Delete(cookie.Value)
	}
	clearSessionCookie(w)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s Server) handleAuthMe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	user, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": user.Username, "role": user.Role})
}

func (s Server) handleAuthPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	current, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
		return
	}
	var req passwordChangeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if len(req.NewPassword) < 6 {
		writeError(w, http.StatusBadRequest, errors.New("密码至少需要 6 个字符"))
		return
	}
	if req.NewPassword != req.ConfirmPassword {
		writeError(w, http.StatusBadRequest, errors.New("两次输入的新密码不一致"))
		return
	}
	if s.LocalDB == nil {
		writeError(w, http.StatusInternalServerError, errors.New("本地配置数据库未初始化"))
		return
	}
	user, found, err := s.LocalDB.FindUser(r.Context(), current.Username)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !found || !validUserCredentials(user, req.OldPassword) {
		writeError(w, http.StatusBadRequest, errors.New("当前密码错误"))
		return
	}
	if err := s.LocalDB.SaveUser(r.Context(), config.User{Username: user.Username, Password: req.NewPassword, Role: user.Role}); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if cookie, err := r.Cookie(authCookieName); err == nil {
		s.Sessions.Delete(cookie.Value)
	}
	clearSessionCookie(w)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "密码已修改，请重新登录"})
}

func (s Server) handleAuthRegister(w http.ResponseWriter, r *http.Request) {
	cfg := s.runtimeConfig()
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":                  true,
			"enable_registration": cfg.EnableRegistration,
			"require_invite":      cfg.RequireInvite,
		})
	case http.MethodPost:
		if !cfg.EnableRegistration {
			writeError(w, http.StatusForbidden, errors.New("注册功能已关闭"))
			return
		}
		if s.LocalDB == nil {
			db, err := config.OpenLocalDB(s.configDBPath())
			if err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			s.LocalDB = db
		}
		var req registerRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		username := strings.TrimSpace(req.Username)
		password := req.Password
		if len(username) < 3 {
			writeError(w, http.StatusBadRequest, errors.New("用户名至少需要 3 个字符"))
			return
		}
		if len(password) < 6 {
			writeError(w, http.StatusBadRequest, errors.New("密码至少需要 6 个字符"))
			return
		}
		user := config.User{Username: username, Password: password, Role: config.RoleUser}
		if err := s.LocalDB.RegisterUser(r.Context(), user, req.InviteCode, cfg.RequireInvite); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		token, expires, err := s.Sessions.Create(username, config.RoleUser)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		setSessionCookie(w, token, expires)
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": username, "role": config.RoleUser})
	default:
		w.Header().Set("Allow", "GET, POST")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

func (s Server) handleUsers(w http.ResponseWriter, r *http.Request) {
	if s.LocalDB == nil {
		writeError(w, http.StatusServiceUnavailable, errors.New("本地用户数据库未初始化"))
		return
	}
	switch r.Method {
	case http.MethodGet:
		users, err := s.LocalDB.ListUsers(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"users": users})
	case http.MethodPost:
		var req userRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		user := config.User{Username: strings.TrimSpace(req.Username), Password: req.Password, Role: config.NormalizeRole(req.Role)}
		if err := s.LocalDB.SaveUser(r.Context(), user); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": user.Username, "role": user.Role})
	default:
		w.Header().Set("Allow", strings.Join([]string{http.MethodGet, http.MethodPost}, ", "))
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

func (s Server) handleInstallTestMySQL(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg, err := s.installConfigFromRequest(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	start := time.Now()
	if err := testMySQLConnection(r.Context(), cfg); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "MySQL 连接成功", "duration_ms": time.Since(start).Milliseconds()})
}

func (s Server) handleInstallTestRedis(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg, err := s.installConfigFromRequest(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	start := time.Now()
	redisCache, err := cache.OpenRedis(r.Context(), cfg)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if redisCache != nil {
		defer redisCache.Close()
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "Redis 连接成功", "duration_ms": time.Since(start).Milliseconds()})
}

func (s Server) installConfigFromRequest(r *http.Request) (config.Config, error) {
	current := s.currentInstallConfig()
	var incoming config.Config
	if err := json.NewDecoder(r.Body).Decode(&incoming); err != nil {
		return config.Config{}, err
	}
	return mergeInstallConfig(current, incoming), nil
}

func (s Server) handleInstallStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg := s.currentInstallConfig()
	err := cfg.ValidateInstall()
	locked := s.installed()
	installed := err == nil && locked && !s.installOnly()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":           true,
		"installed":    installed,
		"install_lock": locked,
		"install_only": s.installOnly(),
		"docker_mode":  dockerInstallMode(),
		"config":       cfg,
		"config_path":  s.configDBPath(),
		"lock_path":    s.configDBPath(),
		"error":        errorString(err),
	})
}

func (s Server) handleInstall(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleInstallStatus(w, r)
		return
	case http.MethodPost:
	default:
		w.Header().Set("Allow", "GET, POST")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}

	current := s.currentInstallConfig()
	var incoming config.Config
	if err := json.NewDecoder(r.Body).Decode(&incoming); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	cfg := normalizeInstallStorage(mergeInstallConfig(current, incoming))
	if err := cfg.ValidateInstall(); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if s.LocalDB == nil {
		db, err := config.OpenLocalDB(s.configDBPath())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.LocalDB = db
	}
	if err := s.LocalDB.SaveConfig(r.Context(), cfg); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	message := "配置已写入本地配置库，安装已生效"
	if err := s.reloadRuntime(r.Context(), cfg); err != nil {
		s.log().Warn("runtime hot reload failed after install, continue with saved config", "error", err)
		if s.Runtime == nil {
			s.Runtime = NewRuntimeState(cfg, true, false, http.DefaultClient, nil, nil, nil, nil)
		} else {
			s.Runtime.Update(cfg, true, false, http.DefaultClient, nil, nil, nil, nil)
		}
		message = "配置已写入本地配置库；部分运行时连接初始化失败，请检查连接测试"
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":           true,
		"installed":    true,
		"install_lock": true,
		"install_only": false,
		"config_path":  s.configDBPath(),
		"lock_path":    s.configDBPath(),
		"message":      message,
	})
}

func (s Server) handleFavicon(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusNoContent)
}

func (s Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	staticDir := s.staticDir()
	requested := filepath.Clean(strings.TrimPrefix(r.URL.Path, "/"))
	if requested == "." {
		requested = ""
	}
	if requested != "" {
		target := filepath.Join(staticDir, requested)
		if info, err := os.Stat(target); err == nil && !info.IsDir() {
			http.ServeFile(w, r, target)
			return
		}
	}
	index := filepath.Join(staticDir, "index.html")
	if _, err := os.Stat(index); err != nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`<!doctype html><meta charset="utf-8"><title>Bangumi PikPak</title><h1>前端还没有构建</h1><p>请先运行：<code>cd frontend && npm install && npm run build</code></p>`))
		return
	}
	http.ServeFile(w, r, index)
}

func (s Server) handleAdminOverview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	lib, updatedAt, _ := s.adminLibrarySnapshot(r.Context())
	animeCount, episodeCount, fileCount, totalBytes := libraryStats(lib)
	usersCount := s.adminUsersCount(r.Context())
	cfg := s.runtimeConfig()
	providerName := cfg.NormalizedStorageProvider()
	writeJSON(w, http.StatusOK, map[string]any{
		"cards": []map[string]any{
			{"label": "总用户数", "value": usersCount, "trend": "本地账号", "icon": "👥", "tone": "purple"},
			{"label": "番剧总数", "value": animeCount, "trend": providerName + " 快照", "icon": "📺", "tone": "orange"},
			{"label": "剧集总数", "value": episodeCount, "trend": "已索引", "icon": "🧩", "tone": "blue"},
			{"label": "文件总数", "value": fileCount, "trend": formatBytes(totalBytes), "icon": "▶", "tone": "green"},
			{"label": "运行时间", "value": formatDuration(time.Since(serverStartedAt)), "trend": "当前进程", "icon": "⏱", "tone": "pink"},
		},
		"library_updated_at": updatedAt.Format(time.RFC3339),
		"anime_count":        animeCount,
		"episode_count":      episodeCount,
		"file_count":         fileCount,
		"storage_bytes":      totalBytes,
		"storage_provider":   providerName,
	})
}

func (s Server) handleAdminAnime(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
	case http.MethodDelete:
		s.handleAdminAnimeDelete(w, r)
		return
	default:
		w.Header().Set("Allow", "GET, DELETE")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	lib, updatedAt, ok := s.adminLibrarySnapshot(r.Context())
	items := make([]map[string]any, 0, len(lib.Bangumi))
	for _, item := range lib.Bangumi {
		episodes, files, size := bangumiStats(item)
		items = append(items, map[string]any{
			"id":            item.ID,
			"title":         item.Title,
			"cover_url":     item.CoverURL,
			"summary":       item.Summary,
			"episodes":      adminEpisodeItems(item),
			"episode_count": episodes,
			"file_count":    files,
			"storage_bytes": size,
			"status":        "已索引",
			"updated_at":    updatedAt.Format("2006-01-02 15:04"),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "snapshot_available": ok, "updated_at": updatedAt.Format(time.RFC3339)})
}

func adminEpisodeItems(item Bangumi) []map[string]any {
	episodes := make([]map[string]any, 0, len(item.Episodes))
	for _, episode := range item.Episodes {
		var size int64
		for _, file := range episode.Files {
			size += file.Size
		}
		episodes = append(episodes, map[string]any{
			"id":            episode.ID,
			"label":         episode.Label,
			"file_count":    len(episode.Files),
			"storage_bytes": size,
			"direct":        strings.HasSuffix(episode.ID, ":direct"),
		})
	}
	return episodes
}

func (s Server) handleAdminAnimeDelete(w http.ResponseWriter, r *http.Request) {
	var req adminAnimeDeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	idSet := make(map[string]struct{}, len(req.IDs))
	titleSet := make(map[string]struct{}, len(req.Titles))
	for _, id := range req.IDs {
		if id = strings.TrimSpace(id); id != "" {
			idSet[id] = struct{}{}
		}
	}
	for _, title := range req.Titles {
		if title = strings.TrimSpace(title); title != "" {
			titleSet[title] = struct{}{}
		}
	}
	if len(idSet) == 0 && len(titleSet) == 0 {
		writeError(w, http.StatusBadRequest, errors.New("请选择要操作的番剧"))
		return
	}
	lib, _, _ := s.adminLibrarySnapshot(r.Context())
	kept := make([]Bangumi, 0, len(lib.Bangumi))
	deletedItems := make([]Bangumi, 0)
	deletedTitles := make([]string, 0)
	for _, item := range lib.Bangumi {
		_, idMatched := idSet[item.ID]
		_, titleMatched := titleSet[item.Title]
		if idMatched || titleMatched {
			deletedItems = append(deletedItems, item)
			deletedTitles = append(deletedTitles, item.Title)
			continue
		}
		kept = append(kept, item)
	}
	if len(deletedTitles) == 0 {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": 0, "items": []map[string]any{}})
		return
	}
	if req.DeleteFiles {
		if err := s.deleteAnimeFiles(r.Context(), deletedItems); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	lib.Bangumi = kept
	if st := s.store(); st != nil {
		if _, err := st.DeleteBangumi(r.Context(), deletedTitles); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if err := st.SaveSnapshot(r.Context(), librarySnapshotKey, lib); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": len(deletedTitles), "deleted_files": req.DeleteFiles, "deleted_titles": deletedTitles})
}

func (s Server) deleteAnimeFiles(ctx context.Context, items []Bangumi) error {
	provider := s.storageProvider()
	if provider == nil {
		return errors.New("储存桶未初始化")
	}
	deleter, ok := provider.(storage.DeleteCapable)
	if !ok {
		return fmt.Errorf("%s 储存桶不支持删除文件", provider.Name())
	}
	for _, item := range items {
		folder := storage.Folder{ID: item.ID, Name: item.Title}
		if strings.HasPrefix(item.ID, "local:") {
			path, err := decodeLocalStreamID(item.ID)
			if err != nil {
				return fmt.Errorf("解析本地番剧目录 ID 失败（%q）：%w", item.Title, err)
			}
			folder.ID = path
			folder.Path = path
		}
		if err := deleter.DeleteBangumi(ctx, folder); err != nil {
			return fmt.Errorf("删除 %q 文件失败：%w", item.Title, err)
		}
	}
	return nil
}

func (s Server) handleAdminAnimeEpisode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.Header().Set("Allow", http.MethodDelete)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req adminEpisodeDeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.BangumiID = strings.TrimSpace(req.BangumiID)
	req.BangumiTitle = strings.TrimSpace(req.BangumiTitle)
	req.EpisodeID = strings.TrimSpace(req.EpisodeID)
	req.EpisodeLabel = strings.TrimSpace(req.EpisodeLabel)
	if (req.BangumiID == "" && req.BangumiTitle == "") || (req.EpisodeID == "" && req.EpisodeLabel == "") {
		writeError(w, http.StatusBadRequest, errors.New("番剧和剧集不能为空"))
		return
	}

	lib, _, _ := s.adminLibrarySnapshot(r.Context())
	var deletedEpisode Episode
	var deletedTitle string
	found := false
	for i := range lib.Bangumi {
		if req.BangumiID != "" && lib.Bangumi[i].ID != req.BangumiID {
			continue
		}
		if req.BangumiTitle != "" && lib.Bangumi[i].Title != req.BangumiTitle {
			continue
		}
		keptEpisodes := make([]Episode, 0, len(lib.Bangumi[i].Episodes))
		for _, episode := range lib.Bangumi[i].Episodes {
			idMatched := req.EpisodeID != "" && episode.ID == req.EpisodeID
			labelMatched := req.EpisodeLabel != "" && episode.Label == req.EpisodeLabel
			if idMatched || labelMatched {
				deletedEpisode = episode
				deletedTitle = lib.Bangumi[i].Title
				found = true
				continue
			}
			keptEpisodes = append(keptEpisodes, episode)
		}
		lib.Bangumi[i].Episodes = keptEpisodes
		break
	}
	if !found {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": 0})
		return
	}
	if req.DeleteFiles {
		if strings.HasSuffix(deletedEpisode.ID, ":direct") {
			writeError(w, http.StatusBadRequest, errors.New("直接文件分组不能按文件夹删除"))
			return
		}
		if err := s.deleteEpisodeFiles(r.Context(), deletedEpisode); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	if st := s.store(); st != nil {
		if _, err := st.DeleteEpisode(r.Context(), deletedTitle, deletedEpisode.Label); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if err := st.SaveSnapshot(r.Context(), librarySnapshotKey, lib); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": 1, "deleted_files": req.DeleteFiles, "bangumi_title": deletedTitle, "episode_label": deletedEpisode.Label})
}

func (s Server) handleAdminDownloadRequests(w http.ResponseWriter, r *http.Request) {
	if s.LocalDB == nil {
		db, err := config.OpenLocalDB(s.configDBPath())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.LocalDB = db
	}
	switch r.Method {
	case http.MethodGet:
		items, err := s.LocalDB.ListDownloadRequests(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"items": items})
	case http.MethodPost:
		var req adminDownloadRequestAction
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if req.ID <= 0 {
			writeError(w, http.StatusBadRequest, errors.New("ID 不能为空"))
			return
		}
		action := strings.ToLower(strings.TrimSpace(req.Action))
		if action == "" {
			action = "approve"
		}
		item, ok, err := s.LocalDB.FindDownloadRequest(r.Context(), req.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			writeError(w, http.StatusNotFound, errors.New("下载申请不存在"))
			return
		}
		switch action {
		case "approve":
			if item.Status != "pending" {
				writeError(w, http.StatusBadRequest, fmt.Errorf("申请状态不是待处理：%s", item.Status))
				return
			}
			_ = s.LocalDB.UpdateDownloadRequestStatus(r.Context(), req.ID, "downloading")
			providerName, err := s.submitDownloadToStorage(r.Context(), downloadRequest{
				Title:        item.Title,
				BangumiTitle: item.BangumiTitle,
				EpisodeLabel: item.EpisodeLabel,
				TorrentURL:   item.TorrentURL,
				Magnet:       item.Magnet,
			})
			if err != nil {
				_ = s.LocalDB.UpdateDownloadRequestStatus(r.Context(), req.ID, "failed")
				writeError(w, http.StatusBadGateway, err)
				return
			}
			if err := s.LocalDB.UpdateDownloadRequestStatus(r.Context(), req.ID, "approved"); err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			items, _ := s.LocalDB.ListDownloadRequests(r.Context())
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "已同意并提交到 " + storageProviderLabel(providerName) + " 下载队列", "items": items})
		case "reject":
			if err := s.LocalDB.UpdateDownloadRequestStatus(r.Context(), req.ID, "rejected"); err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			items, _ := s.LocalDB.ListDownloadRequests(r.Context())
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "已拒绝该下载申请", "items": items})
		default:
			writeError(w, http.StatusBadRequest, errors.New("不支持的操作"))
		}
	default:
		w.Header().Set("Allow", "GET, POST")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

func (s Server) deleteEpisodeFiles(ctx context.Context, episode Episode) error {
	provider := s.storageProvider()
	if provider == nil {
		return errors.New("储存桶未初始化")
	}
	deleter, ok := provider.(storage.DeleteCapable)
	if !ok {
		return fmt.Errorf("%s 储存桶不支持删除文件", provider.Name())
	}
	folder := storage.Folder{ID: episode.ID, Name: episode.Label}
	if strings.HasPrefix(episode.ID, "local:") {
		path, err := decodeLocalStreamID(episode.ID)
		if err != nil {
			return fmt.Errorf("解析本地剧集 ID 失败（%q）：%w", episode.Label, err)
		}
		folder.ID = path
		folder.Path = path
	}
	if err := deleter.DeleteBangumi(ctx, folder); err != nil {
		return fmt.Errorf("删除剧集 %q 文件失败：%w", episode.Label, err)
	}
	return nil
}

func (s Server) handleAdminLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg := s.runtimeConfig()
	now := time.Now()
	entries := []map[string]any{
		{"time": now.Format("2006-01-02 15:04:05"), "level": "INFO", "module": "admin", "message": "管理员面板数据刷新完成"},
		{"time": now.Add(-3 * time.Minute).Format("2006-01-02 15:04:05"), "level": "INFO", "module": "runtime", "message": "运行配置已加载，安装状态正常"},
		{"time": now.Add(-8 * time.Minute).Format("2006-01-02 15:04:05"), "level": "INFO", "module": "mysql", "message": enabledText(s.store() != nil, "MySQL 存储已连接", "MySQL 存储未初始化")},
		{"time": now.Add(-13 * time.Minute).Format("2006-01-02 15:04:05"), "level": "INFO", "module": "redis", "message": enabledText(s.redisCache() != nil, "Redis 缓存已连接", "Redis 缓存未初始化")},
		{"time": now.Add(-21 * time.Minute).Format("2006-01-02 15:04:05"), "level": "INFO", "module": "proxy", "message": enabledText(cfg.EnableProxy, "代理配置已启用", "代理配置未启用")},
	}
	writeJSON(w, http.StatusOK, map[string]any{"logs": entries})
}

func (s Server) handleAdminConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		cfg := s.currentInstallConfig()
		writeJSON(w, http.StatusOK, map[string]any{"config": adminEditableConfig(cfg)})
	case http.MethodPost:
		current := s.currentInstallConfig()
		var incoming config.Config
		if err := json.NewDecoder(r.Body).Decode(&incoming); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		cfg := mergeAdminEditableConfig(current, incoming)
		if err := cfg.Validate(); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if s.LocalDB == nil {
			db, err := config.OpenLocalDB(s.configDBPath())
			if err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			s.LocalDB = db
		}
		if err := s.LocalDB.SaveConfig(r.Context(), cfg); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		message := "配置已保存并热加载"
		if err := s.reloadRuntime(r.Context(), cfg); err != nil {
			s.log().Warn("runtime hot reload failed after admin config save", "error", err)
			if s.Runtime == nil {
				s.Runtime = NewRuntimeState(cfg, true, false, http.DefaultClient, nil, nil, nil, nil)
			} else {
				s.Runtime.Update(cfg, true, false, http.DefaultClient, nil, nil, nil, nil)
			}
			message = "配置已保存；部分运行时连接初始化失败，请检查 PikPak / MySQL / Redis 配置"
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": message, "config": adminEditableConfig(cfg)})
	default:
		w.Header().Set("Allow", "GET, POST")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

func (s Server) handleAdminInviteCodes(w http.ResponseWriter, r *http.Request) {
	if s.LocalDB == nil {
		db, err := config.OpenLocalDB(s.configDBPath())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.LocalDB = db
	}
	switch r.Method {
	case http.MethodGet:
		codes, err := s.LocalDB.ListInviteCodes(r.Context())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"codes": codes})
	case http.MethodPost:
		var req inviteCodeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		count := req.Count
		if count <= 0 {
			count = 1
		}
		if count > 100 {
			writeError(w, http.StatusBadRequest, errors.New("一次最多生成 100 个邀请码"))
			return
		}
		expiresAt, err := normalizeInviteExpiresAt(req.ExpiresAt)
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		created := make([]string, 0, count)
		for len(created) < count {
			code, err := generateInviteCode()
			if err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			if err := s.LocalDB.SaveInviteCode(r.Context(), code, expiresAt); err != nil {
				if strings.Contains(err.Error(), "UNIQUE") {
					continue
				}
				writeError(w, http.StatusInternalServerError, err)
				return
			}
			created = append(created, code)
		}
		codes, _ := s.LocalDB.ListInviteCodes(r.Context())
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "codes_created": created, "codes": codes})
	case http.MethodDelete:
		var req inviteCodeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		deleted, err := s.LocalDB.DeleteInviteCodes(r.Context(), req.Codes)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		codes, _ := s.LocalDB.ListInviteCodes(r.Context())
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": deleted, "codes": codes})
	default:
		w.Header().Set("Allow", "GET, POST, DELETE")
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
	}
}

func adminEditableConfig(cfg config.Config) map[string]any {
	return map[string]any{
		"username":                  cfg.Username,
		"password":                  cfg.Password,
		"pikpak_auth_mode":          cfg.PikPakAuthMode,
		"pikpak_access_token":       cfg.PikPakAccessToken,
		"pikpak_refresh_token":      cfg.PikPakRefreshToken,
		"pikpak_encoded_token":      cfg.PikPakEncodedToken,
		"path":                      cfg.Path,
		"rss":                       cfg.RSS,
		"mikan_username":            cfg.MikanUsername,
		"mikan_password":            cfg.MikanPassword,
		"require_login":             cfg.RequireLogin,
		"enable_registration":       cfg.EnableRegistration,
		"require_invite":            cfg.RequireInvite,
		"user_daily_download_limit": cfg.UserDailyDownloadLimit,
		"storage_provider":          cfg.NormalizedStorageProvider(),
		"drive115_cookie":           cfg.Drive115Cookie,
		"drive115_root_cid":         cfg.Drive115RootCID,
		"aria2_rpc_url":             cfg.Aria2RPCURL,
		"aria2_rpc_secret":          cfg.Aria2RPCSecret,
		"local_storage_path":        cfg.LocalStoragePath,
		"nas_storage_path":          cfg.NASStoragePath,
	}
}

func mergeAdminEditableConfig(current, incoming config.Config) config.Config {
	current.Username = incoming.Username
	current.Password = incoming.Password
	current.PikPakAuthMode = firstNonEmpty(incoming.PikPakAuthMode, current.PikPakAuthMode, config.Default().PikPakAuthMode)
	current.PikPakAccessToken = incoming.PikPakAccessToken
	current.PikPakRefreshToken = incoming.PikPakRefreshToken
	current.PikPakEncodedToken = incoming.PikPakEncodedToken
	current.Path = incoming.Path
	current.RSS = incoming.RSS
	current.MikanUsername = incoming.MikanUsername
	current.MikanPassword = incoming.MikanPassword
	current.RequireLogin = incoming.RequireLogin
	current.EnableRegistration = incoming.EnableRegistration
	current.RequireInvite = incoming.RequireInvite
	current.UserDailyDownloadLimit = incoming.UserDailyDownloadLimit
	current.StorageProvider = firstNonEmpty(incoming.StorageProvider, current.StorageProvider, config.Default().StorageProvider)
	current.Drive115Cookie = incoming.Drive115Cookie
	current.Drive115RootCID = firstNonEmpty(incoming.Drive115RootCID, current.Drive115RootCID, config.Default().Drive115RootCID)
	current.Aria2RPCURL = firstNonEmpty(incoming.Aria2RPCURL, current.Aria2RPCURL, config.Default().Aria2RPCURL)
	current.Aria2RPCSecret = incoming.Aria2RPCSecret
	current.LocalStoragePath = firstNonEmpty(incoming.LocalStoragePath, current.LocalStoragePath, config.Default().LocalStoragePath)
	current.NASStoragePath = incoming.NASStoragePath
	return installConfigWithDefaults(current)
}

func (s Server) handleAdminMonitor(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	cfg := s.runtimeConfig()
	writeJSON(w, http.StatusOK, map[string]any{
		"uptime":           formatDuration(time.Since(serverStartedAt)),
		"goroutines":       runtime.NumGoroutine(),
		"memory_alloc":     mem.Alloc,
		"memory_sys":       mem.Sys,
		"mysql_ready":      s.store() != nil,
		"redis_ready":      s.redisCache() != nil,
		"pikpak_ready":     s.pikpakClient() != nil,
		"storage_ready":    s.storageProvider() != nil,
		"storage_provider": cfg.NormalizedStorageProvider(),
		"installed":        s.installed(),
		"install_only":     s.installOnly(),
		"proxy_enabled":    cfg.EnableProxy,
		"rss_configured":   strings.TrimSpace(cfg.RSS) != "",
		"path_configured":  strings.TrimSpace(cfg.Path) != "",
		"checked_at":       time.Now().Format(time.RFC3339),
	})
}

func (s Server) adminLibrarySnapshot(ctx context.Context) (LibraryResponse, time.Time, bool) {
	if lib, updatedAt, ok := s.loadCachedLibrary(ctx); ok {
		return lib, updatedAt, true
	}
	return LibraryResponse{}, time.Time{}, false
}

func (s Server) adminUsersCount(ctx context.Context) int {
	if s.LocalDB == nil {
		return 0
	}
	users, err := s.LocalDB.ListUsers(ctx)
	if err != nil {
		return 0
	}
	return len(users)
}

func libraryStats(lib LibraryResponse) (animeCount, episodeCount, fileCount int, totalBytes int64) {
	animeCount = len(lib.Bangumi)
	for _, item := range lib.Bangumi {
		episodes, files, size := bangumiStats(item)
		episodeCount += episodes
		fileCount += files
		totalBytes += size
	}
	return animeCount, episodeCount, fileCount, totalBytes
}

func bangumiStats(item Bangumi) (episodes, files int, totalBytes int64) {
	episodes = len(item.Episodes)
	for _, ep := range item.Episodes {
		files += len(ep.Files)
		for _, file := range ep.Files {
			totalBytes += file.Size
		}
	}
	return episodes, files, totalBytes
}

func formatBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for n/div >= unit && exp < 4 {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(n)/float64(div), "KMGTPE"[exp])
}

func generateInviteCode() (string, error) {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	raw := strings.ToUpper(hex.EncodeToString(buf))
	return raw[:4] + "-" + raw[4:8] + "-" + raw[8:12] + "-" + raw[12:], nil
}

func normalizeInviteExpiresAt(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", nil
	}
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return "", fmt.Errorf("过期时间格式无效")
	}
	if time.Now().After(t) {
		return "", fmt.Errorf("过期时间必须晚于当前时间")
	}
	return t.Format(time.RFC3339), nil
}

func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm", int(d.Minutes()))
	}
	if d < 24*time.Hour {
		return fmt.Sprintf("%dh %dm", int(d.Hours()), int(d.Minutes())%60)
	}
	return fmt.Sprintf("%dd %dh", int(d.Hours())/24, int(d.Hours())%24)
}

func enabledText(ok bool, yes, no string) string {
	if ok {
		return yes
	}
	return no
}

func chinaDayStart(now time.Time) time.Time {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		loc = time.FixedZone("CST", 8*60*60)
	}
	t := now.In(loc)
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, loc)
}

func (s Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	cfg := s.runtimeConfig()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":              true,
		"rss_configured":  strings.TrimSpace(cfg.RSS) != "",
		"path_configured": strings.TrimSpace(cfg.Path) != "",
		"require_login":   cfg.RequireLogin,
		"torrent_root":    s.torrentRoot(),
		"time":            time.Now().Format(time.RFC3339),
	})
}

func (s Server) handleLibrary(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cfg := s.runtimeConfig()
	forceRefresh := r.URL.Query().Get("refresh") == "1"
	if !forceRefresh {
		if lib, updatedAt, ok := s.loadCachedLibrary(ctx); ok && time.Since(updatedAt) < librarySnapshotTTL {
			s.log().Info("serve library from mysql snapshot", "age", time.Since(updatedAt).String())
			writeJSON(w, http.StatusOK, lib)
			return
		}
	}
	if user, ok := s.authenticatedUser(r); !ok || user.Role != config.RoleAdmin {
		if lib, updatedAt, ok := s.loadCachedLibrary(ctx); ok {
			s.log().Info("serve stale library snapshot to ordinary user", "age", time.Since(updatedAt).String())
			writeJSON(w, http.StatusOK, lib)
			return
		}
		writeError(w, http.StatusForbidden, errors.New("媒体库快照不可用，请管理员先扫描媒体库"))
		return
	}
	lib, err := s.buildStorageLibrary(ctx, cfg)
	if err != nil {
		if lib, updatedAt, ok := s.loadCachedLibrary(ctx); ok {
			s.log().Warn("storage library scan failed, serve stale snapshot", "provider", cfg.NormalizedStorageProvider(), "age", time.Since(updatedAt).String(), "error", err)
			writeJSON(w, http.StatusOK, lib)
			return
		}
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if err := s.applyStoredLibraryMetadata(ctx, &lib); err != nil {
		s.log().Warn("mysql library metadata enrichment failed", "error", err)
	}
	if err := enrichLibraryCovers(ctx, &lib, s.coverResolver(), s.torrentRoot(), s.log()); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if err := s.saveLibraryToStore(ctx, lib); err != nil {
		s.log().Warn("mysql library upsert failed", "error", err)
	}
	if st := s.store(); st != nil {
		if err := st.SaveSnapshot(ctx, librarySnapshotKey, lib); err != nil {
			s.log().Warn("mysql library snapshot save failed", "error", err)
		}
	}
	writeJSON(w, http.StatusOK, lib)
}

func (s Server) buildStorageLibrary(ctx context.Context, cfg config.Config) (LibraryResponse, error) {
	switch cfg.NormalizedStorageProvider() {
	case "pikpak":
		drive := s.pikpakClient()
		if drive == nil {
			return LibraryResponse{}, errors.New("pikpak client is not initialized")
		}
		if err := drive.Login(); err != nil {
			return LibraryResponse{}, fmt.Errorf("PikPak 登录失败：%w", err)
		}
		return BuildLibrary(ctx, drive, cfg.Path, s.torrentRoot())
	case "local":
		return BuildLocalLibrary(ctx, cfg.LocalStoragePath, s.torrentRoot())
	case "nas":
		return BuildLocalLibrary(ctx, cfg.NASStoragePath, s.torrentRoot())
	case "drive115":
		drive := newDrive115DriveClient(cfg.Drive115Cookie, s.httpClient())
		if err := drive.Login(); err != nil {
			return LibraryResponse{}, err
		}
		rootID := strings.TrimSpace(cfg.Drive115RootCID)
		if rootID == "" {
			rootID = "0"
		}
		return BuildLibrary(ctx, drive, rootID, s.torrentRoot())
	default:
		return LibraryResponse{}, fmt.Errorf("不支持的储存桶类型：%s", cfg.StorageProvider)
	}
}

func (s Server) refreshLibrarySnapshot(ctx context.Context) error {
	cfg := s.runtimeConfig()
	lib, err := s.buildStorageLibrary(ctx, cfg)
	if err != nil {
		return err
	}
	if err := s.applyStoredLibraryMetadata(ctx, &lib); err != nil {
		s.log().Warn("mysql library metadata enrichment failed", "error", err)
	}
	if err := enrichLibraryCovers(ctx, &lib, s.coverResolver(), s.torrentRoot(), s.log()); err != nil {
		return err
	}
	if err := s.saveLibraryToStore(ctx, lib); err != nil {
		return err
	}
	if st := s.store(); st != nil {
		if err := st.SaveSnapshot(ctx, librarySnapshotKey, lib); err != nil {
			return err
		}
	}
	return nil
}

func (s Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeJSON(w, http.StatusOK, map[string]any{"results": []mikan.SearchResult{}})
		return
	}
	cacheKey := "search:mikan:v2:" + q
	if rc := s.redisCache(); rc != nil {
		var cached searchResponse
		if ok, err := rc.GetJSON(r.Context(), cacheKey, &cached); err == nil && ok {
			s.log().Info("serve mikan search from redis", "query", q)
			writeJSON(w, http.StatusOK, cached)
			return
		} else if err != nil {
			s.log().Warn("redis mikan search read failed", "query", q, "error", err)
		}
	}
	results, matchedQuery, err := s.searchMikanWithFallback(r.Context(), q, 18)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	for i := range results {
		if i >= 10 {
			break
		}
		meta, err := mikan.FetchEpisodeMetadata(s.httpClient(), results[i].Link)
		if err != nil {
			s.log().Warn("mikan metadata enrichment failed", "title", results[i].Title, "error", err)
			continue
		}
		results[i].BangumiTitle = meta.Title
		if bgmMeta, err := s.coverResolver().SearchMetadata(meta.Title); err == nil && (bgmMeta.CoverURL != "" || bgmMeta.Summary != "") {
			results[i].CoverURL = bgmMeta.CoverURL
			results[i].Summary = bgmMeta.Summary
		} else {
			results[i].CoverURL = meta.CoverURL
		}
	}
	resp := searchResponse{Results: results, Query: q, MatchedQuery: matchedQuery}
	if rc := s.redisCache(); rc != nil {
		if err := rc.SetJSON(r.Context(), cacheKey, resp, externalCacheTTL); err != nil {
			s.log().Warn("redis mikan search write failed", "query", q, "error", err)
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s Server) searchMikanWithFallback(ctx context.Context, q string, limit int) ([]mikan.SearchResult, string, error) {
	candidates := []string{q}
	if subjects, err := s.coverResolver().SearchSubjects(q, 5); err == nil {
		for _, subject := range subjects {
			candidates = append(candidates, subject.Name, subject.NameCN)
		}
	} else {
		s.log().Warn("bangumi fallback keyword lookup failed", "query", q, "error", err)
	}
	candidates = append(candidates, cjkFallbackKeywords(q)...)
	candidates = uniqueNonEmpty(candidates)
	var lastErr error
	for _, candidate := range candidates {
		select {
		case <-ctx.Done():
			return nil, "", ctx.Err()
		default:
		}
		results, err := mikan.Search(s.httpClient(), candidate, limit)
		if err != nil {
			lastErr = err
			s.log().Warn("mikan search candidate failed", "query", q, "candidate", candidate, "error", err)
			continue
		}
		if len(results) > 0 {
			if candidate != q {
				s.log().Info("mikan search fallback matched", "query", q, "matched_query", candidate, "count", len(results))
			}
			return results, candidate, nil
		}
	}
	if lastErr != nil {
		return nil, "", lastErr
	}
	return []mikan.SearchResult{}, "", nil
}

func uniqueNonEmpty(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		key := strings.ToLower(value)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, value)
	}
	return out
}

func cjkFallbackKeywords(q string) []string {
	normalized := make([]rune, 0, len(q))
	for _, r := range q {
		if unicode.Is(unicode.Han, r) {
			normalized = append(normalized, r)
		}
	}
	if len(normalized) < 4 || len(normalized) > 12 {
		return nil
	}
	out := make([]string, 0, 6)
	for size := minInt(4, len(normalized)-1); size >= 2; size-- {
		for i := 0; i+size <= len(normalized); i++ {
			out = append(out, string(normalized[i:i+size]))
			if len(out) >= 6 {
				return out
			}
		}
	}
	return out
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func (s Server) handleBangumiDiscover(w http.ResponseWriter, r *http.Request) {
	section := strings.TrimSpace(r.URL.Query().Get("section"))
	tag := strings.TrimSpace(r.URL.Query().Get("tag"))
	limit := queryInt(r, "limit", 24)
	offset := queryInt(r, "offset", 0)
	if limit <= 0 || limit > 50 {
		limit = 24
	}
	cacheKey := fmt.Sprintf("bangumi:discover:%s:%s:%d:%d", section, tag, limit, offset)
	if rc := s.redisCache(); rc != nil {
		var cached map[string]any
		if ok, err := rc.GetJSON(r.Context(), cacheKey, &cached); err == nil && ok {
			s.log().Info("serve bangumi discover from redis", "section", section, "tag", tag, "offset", offset)
			writeJSON(w, http.StatusOK, cached)
			return
		} else if err != nil {
			s.log().Warn("redis bangumi discover read failed", "error", err)
		}
	}
	items, err := s.coverResolver().DiscoverPage(section, tag, limit, offset)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	resp := map[string]any{"subjects": items, "limit": limit, "offset": offset, "has_more": len(items) == limit}
	if rc := s.redisCache(); rc != nil {
		if err := rc.SetJSON(r.Context(), cacheKey, resp, externalCacheTTL); err != nil {
			s.log().Warn("redis bangumi discover write failed", "error", err)
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s Server) handleMikanSchedule(w http.ResponseWriter, r *http.Request) {
	year := 0
	if raw := strings.TrimSpace(r.URL.Query().Get("year")); raw != "" {
		_, _ = fmt.Sscanf(raw, "%d", &year)
	}
	season := strings.TrimSpace(r.URL.Query().Get("season"))
	coverMode := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("cover")))
	limitParam := queryInt(r, "limit", 0)
	cacheKey := fmt.Sprintf("mikan:schedule:%d:%s:%s:%d", year, season, coverMode, limitParam)
	if rc := s.redisCache(); rc != nil {
		var cached mikan.ScheduleResponse
		if ok, err := rc.GetJSON(r.Context(), cacheKey, &cached); err == nil && ok {
			s.log().Info("serve mikan schedule from redis", "year", year, "season", season, "cover", coverMode)
			writeJSON(w, http.StatusOK, cached)
			return
		} else if err != nil {
			s.log().Warn("redis mikan schedule read failed", "error", err)
		}
	}
	schedule, err := mikan.FetchSchedule(s.httpClient(), year, season)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if coverMode == "bangumi" {
		limit := limitParam
		if limit == 0 {
			limit = len(schedule.Items)
		}
		if limit <= 0 || limit > len(schedule.Items) {
			limit = len(schedule.Items)
		}
		s.enrichMikanScheduleCovers(r.Context(), &schedule, limit)
	}
	if rc := s.redisCache(); rc != nil {
		if err := rc.SetJSON(r.Context(), cacheKey, schedule, externalCacheTTL); err != nil {
			s.log().Warn("redis mikan schedule write failed", "error", err)
		}
	}
	writeJSON(w, http.StatusOK, schedule)
}

func (s Server) enrichMikanScheduleCovers(ctx context.Context, schedule *mikan.ScheduleResponse, limit int) {
	if schedule == nil || limit <= 0 {
		return
	}
	resolver := s.coverResolver()
	coverByID := make(map[int]string)
	coverByTitle := make(map[string]string)
	for i := range schedule.Items {
		if i >= limit {
			break
		}
		select {
		case <-ctx.Done():
			return
		default:
		}
		var meta bangumi.Metadata
		if schedule.Items[i].PageURL != "" {
			subjectID, err := mikan.FetchBangumiSubjectID(s.httpClient(), schedule.Items[i].PageURL)
			if err == nil && subjectID > 0 {
				subject, err := resolver.GetSubject(subjectID)
				if err == nil {
					meta = bangumi.Metadata{ID: subject.ID, Title: firstNonEmpty(subject.NameCN, subject.Name), CoverURL: subject.CoverURL(), Summary: subject.Summary}
				} else {
					s.log().Warn("bangumi.tv subject cover lookup failed", "title", schedule.Items[i].Title, "subject_id", subjectID, "error", err)
				}
			}
		}
		if meta.CoverURL == "" {
			var err error
			meta, err = resolver.SearchMetadata(schedule.Items[i].Title)
			if err != nil {
				s.log().Warn("bangumi.tv schedule cover lookup failed", "title", schedule.Items[i].Title, "error", err)
				continue
			}
		}
		if meta.CoverURL == "" {
			continue
		}
		schedule.Items[i].CoverURL = meta.CoverURL
		schedule.Items[i].CoverFrom = "bangumi"
		if schedule.Items[i].ID > 0 {
			coverByID[schedule.Items[i].ID] = meta.CoverURL
		}
		coverByTitle[schedule.Items[i].Title] = meta.CoverURL
	}
	for d := range schedule.Days {
		for i := range schedule.Days[d].Items {
			if cover, ok := coverByID[schedule.Days[d].Items[i].ID]; ok {
				schedule.Days[d].Items[i].CoverURL = cover
				schedule.Days[d].Items[i].CoverFrom = "bangumi"
				continue
			}
			if cover, ok := coverByTitle[schedule.Days[d].Items[i].Title]; ok {
				schedule.Days[d].Items[i].CoverURL = cover
				schedule.Days[d].Items[i].CoverFrom = "bangumi"
			}
		}
	}
}

type subscribeRequest struct {
	SubjectID int    `json:"subject_id"`
	Title     string `json:"title"`
	CoverURL  string `json:"cover_url"`
	Summary   string `json:"summary"`
	Language  int    `json:"language"`
}

func (s Server) handleMikanSubscribe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg := s.runtimeConfig()
	if !cfg.MikanConfigured() {
		writeError(w, http.StatusBadRequest, errors.New("Mikan 用户名或密码未配置"))
		return
	}
	var req subscribeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	if req.Title == "" {
		writeError(w, http.StatusBadRequest, errors.New("标题不能为空"))
		return
	}
	client := mikan.NewSession(s.httpClient())
	if err := mikan.Login(client, cfg.MikanUsername, cfg.MikanPassword); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	candidate, err := mikan.FindBangumiCandidate(client, req.Title)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if err := mikan.SubscribeBangumi(client, candidate.ID, req.Language); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if st := s.store(); st != nil {
		if err := st.SaveSubscription(r.Context(), store.BangumiRecord{Title: req.Title, CoverURL: firstNonEmpty(req.CoverURL, candidate.CoverURL), Summary: req.Summary, BangumiSubjectID: req.SubjectID, MikanBangumiID: candidate.ID}, req.Language); err != nil {
			s.log().Warn("mysql subscription save failed", "title", req.Title, "error", err)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "已在 Mikan 订阅", "mikan_bangumi": candidate})
}

func (s Server) applyStoredLibraryMetadata(ctx context.Context, lib *LibraryResponse) error {
	st := s.store()
	if st == nil || lib == nil {
		return nil
	}
	for i := range lib.Bangumi {
		rec, ok, err := st.Metadata(ctx, lib.Bangumi[i].Title)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		if lib.Bangumi[i].CoverURL == "" {
			lib.Bangumi[i].CoverURL = rec.CoverURL
		}
		if lib.Bangumi[i].Summary == "" {
			lib.Bangumi[i].Summary = rec.Summary
		}
	}
	return nil
}

func (s Server) saveLibraryToStore(ctx context.Context, lib LibraryResponse) error {
	st := s.store()
	if st == nil {
		return nil
	}
	for _, item := range lib.Bangumi {
		if err := st.UpsertBangumi(ctx, store.BangumiRecord{Title: item.Title, PikPakFolderID: item.ID, CoverURL: item.CoverURL, Summary: item.Summary}); err != nil {
			return err
		}
	}
	return nil
}

func (s Server) loadCachedLibrary(ctx context.Context) (LibraryResponse, time.Time, bool) {
	st := s.store()
	if st == nil {
		return LibraryResponse{}, time.Time{}, false
	}
	var lib LibraryResponse
	updatedAt, ok, err := st.LoadSnapshot(ctx, librarySnapshotKey, &lib)
	if err != nil {
		s.log().Warn("mysql library snapshot load failed", "error", err)
		return LibraryResponse{}, time.Time{}, false
	}
	return lib, updatedAt, ok
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func queryInt(r *http.Request, key string, fallback int) int {
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return n
}

func (s Server) handleDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	var req downloadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.TorrentURL = strings.TrimSpace(req.TorrentURL)
	req.Magnet = strings.TrimSpace(req.Magnet)
	downloadURL := req.TorrentURL
	if downloadURL == "" {
		downloadURL = req.Magnet
	}
	if req.Title == "" || downloadURL == "" {
		writeError(w, http.StatusBadRequest, errors.New("标题和 torrent 链接或 magnet 链接不能为空"))
		return
	}
	providerName, err := s.submitDownloadToStorage(r.Context(), req)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "已提交到 " + storageProviderLabel(providerName) + " 下载队列"})
}

func (s Server) submitDownloadToStorage(ctx context.Context, req downloadRequest) (string, error) {
	req.Title = strings.TrimSpace(req.Title)
	req.BangumiTitle = strings.TrimSpace(req.BangumiTitle)
	req.TorrentURL = strings.TrimSpace(req.TorrentURL)
	req.Magnet = strings.TrimSpace(req.Magnet)
	downloadURL := req.TorrentURL
	if downloadURL == "" {
		downloadURL = req.Magnet
	}
	if req.Title == "" || downloadURL == "" {
		return "", errors.New("标题和 torrent 链接或 magnet 链接不能为空")
	}
	if req.BangumiTitle == "" && req.Link != "" {
		if meta, err := mikan.FetchEpisodeMetadata(s.httpClient(), req.Link); err == nil {
			req.BangumiTitle = meta.Title
			req.CoverURL = meta.CoverURL
		} else {
			s.log().Warn("mikan metadata resolve failed before download", "title", req.Title, "error", err)
		}
	}
	if req.BangumiTitle == "" {
		req.BangumiTitle = req.Title
	}
	if bgmMeta, err := s.coverResolver().SearchMetadata(req.BangumiTitle); err == nil && (bgmMeta.CoverURL != "" || bgmMeta.Summary != "") {
		req.CoverURL = bgmMeta.CoverURL
		req.Summary = bgmMeta.Summary
	} else if err != nil {
		s.log().Warn("bangumi.tv metadata lookup failed before download", "bangumi", req.BangumiTitle, "error", err)
	}
	cfg := s.runtimeConfig()
	provider := s.storageProvider()
	if provider == nil {
		if drive := s.pikpakClient(); drive != nil {
			provider = storage.NewPikPakProvider(drive, cfg.Path)
		}
	}
	if provider == nil {
		return "", errors.New("储存桶未初始化")
	}
	runner := app.Runner{
		Config:      cfg,
		HTTPClient:  s.httpClient(),
		Logger:      s.log(),
		TorrentRoot: s.torrentRoot(),
		Storage:     provider,
		Store:       s.store(),
		Strict:      true,
		EntriesFunc: func(context.Context) ([]app.ResolvedEntry, error) {
			return []app.ResolvedEntry{{
				Entry:        rss.Entry{Title: req.Title, Link: req.Link, TorrentURL: downloadURL},
				BangumiTitle: req.BangumiTitle,
				EpisodeLabel: req.EpisodeLabel,
				CoverURL:     req.CoverURL,
				Summary:      req.Summary,
			}}, nil
		},
	}
	if err := runner.RunOnce(ctx); err != nil {
		return "", err
	}
	if err := s.refreshLibrarySnapshot(ctx); err != nil {
		s.log().Warn("refresh library snapshot after download submit failed", "provider", provider.Name(), "error", err)
	}
	return provider.Name(), nil
}

func (s Server) handleDownloadRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	user, ok := s.authenticatedUser(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("请登录后下载"))
		return
	}
	if user.Role == config.RoleAdmin {
		s.handleDownload(w, r)
		return
	}
	if s.LocalDB == nil {
		db, err := config.OpenLocalDB(s.configDBPath())
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.LocalDB = db
	}
	var req downloadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.BangumiTitle = strings.TrimSpace(req.BangumiTitle)
	req.EpisodeLabel = strings.TrimSpace(req.EpisodeLabel)
	req.TorrentURL = strings.TrimSpace(req.TorrentURL)
	req.Magnet = strings.TrimSpace(req.Magnet)
	if req.Title == "" || (req.TorrentURL == "" && req.Magnet == "") {
		writeError(w, http.StatusBadRequest, errors.New("标题和 torrent 链接或 magnet 链接不能为空"))
		return
	}
	limit := s.runtimeConfig().UserDailyDownloadLimit
	used := 0
	if limit > 0 {
		var err error
		used, err = s.LocalDB.CountDownloadRequestsSince(r.Context(), user.Username, chinaDayStart(time.Now()))
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if used >= limit {
			writeError(w, http.StatusTooManyRequests, fmt.Errorf("今日申请下载次数已用完（%d/%d）", used, limit))
			return
		}
	}
	if req.BangumiTitle == "" {
		req.BangumiTitle = req.Title
	}
	id, err := s.LocalDB.SaveDownloadRequest(r.Context(), config.DownloadRequest{
		Username:     user.Username,
		Title:        req.Title,
		BangumiTitle: req.BangumiTitle,
		EpisodeLabel: req.EpisodeLabel,
		TorrentURL:   req.TorrentURL,
		Magnet:       req.Magnet,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	remaining := -1
	if limit > 0 {
		remaining = limit - used - 1
		if remaining < 0 {
			remaining = 0
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":        true,
		"id":        id,
		"message":   "申请已提交，等待管理员下载",
		"used":      used + 1,
		"limit":     limit,
		"remaining": remaining,
	})
}

func (s Server) handleSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	provider := s.storageProvider()
	if provider == nil {
		if drive := s.pikpakClient(); drive != nil {
			provider = storage.NewPikPakProvider(drive, s.runtimeConfig().Path)
		}
	}
	if provider == nil {
		writeError(w, http.StatusServiceUnavailable, errors.New("储存桶未初始化"))
		return
	}
	runner := app.Runner{Config: s.runtimeConfig(), HTTPClient: s.httpClient(), Logger: s.log(), TorrentRoot: s.torrentRoot(), Storage: provider, Store: s.store()}
	if err := runner.RunOnce(r.Context()); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "RSS 搜刮同步已完成"})
}

func (s Server) handleStream(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, errors.New("ID 不能为空"))
		return
	}
	cfg := s.runtimeConfig()
	if strings.HasPrefix(id, "local:") {
		path, err := decodeLocalStreamID(id)
		if err != nil {
			writeError(w, http.StatusBadRequest, errors.New("本地播放 ID 无效"))
			return
		}
		if err := validateLocalStreamPath(path, storageRootForConfig(cfg)); err != nil {
			writeError(w, http.StatusForbidden, err)
			return
		}
		http.ServeFile(w, r, path)
		return
	}
	if cfg.NormalizedStorageProvider() == "drive115" {
		drive := newDrive115DriveClient(cfg.Drive115Cookie, s.httpClient())
		if err := drive.Login(); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		u, err := drive.DownloadURL(id)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		http.Redirect(w, r, u, http.StatusFound)
		return
	}
	drive := s.pikpakClient()
	if drive == nil {
		writeError(w, http.StatusServiceUnavailable, errors.New("当前储存桶不支持在线播放，仅支持 PikPak、本地或 NAS 文件"))
		return
	}
	if err := drive.Login(); err != nil {
		writeError(w, http.StatusBadGateway, fmt.Errorf("PikPak 登录失败：%w", err))
		return
	}
	u, err := drive.DownloadURL(id)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	http.Redirect(w, r, u, http.StatusFound)
}

func storageRootForConfig(cfg config.Config) string {
	switch cfg.NormalizedStorageProvider() {
	case "nas":
		return cfg.NASStoragePath
	default:
		return cfg.LocalStoragePath
	}
}

func validateLocalStreamPath(path, root string) error {
	if strings.TrimSpace(root) == "" {
		return errors.New("储存根目录未配置")
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(absRoot, absPath)
	if err != nil {
		return err
	}
	if rel == "." || strings.HasPrefix(rel, "..") || filepath.IsAbs(rel) {
		return errors.New("文件不在储存根目录内")
	}
	info, err := os.Stat(absPath)
	if err != nil {
		return err
	}
	if info.IsDir() || !isPlayableLocal(info.Name()) {
		return errors.New("文件不可播放")
	}
	return nil
}

func (s Server) httpClient() *http.Client {
	_, _, _, hc, _, _, _, _ := s.runtimeSnapshot()
	if hc != nil {
		return hc
	}
	return http.DefaultClient
}

func (s Server) pikpakClient() PikPakClient {
	_, _, _, _, pp, _, _, _ := s.runtimeSnapshot()
	return pp
}

func (s Server) storageProvider() storage.Provider {
	_, _, _, _, _, sp, _, _ := s.runtimeSnapshot()
	return sp
}

func (s Server) store() *store.MySQLStore {
	_, _, _, _, _, _, st, _ := s.runtimeSnapshot()
	return st
}

func (s Server) redisCache() *cache.RedisCache {
	_, _, _, _, _, _, _, rc := s.runtimeSnapshot()
	return rc
}

func (s Server) torrentRoot() string {
	if s.TorrentRoot != "" {
		return s.TorrentRoot
	}
	return "torrent"
}

func (s Server) staticDir() string {
	if s.StaticDir != "" {
		return s.StaticDir
	}
	return filepath.Join("frontend", "dist")
}

func (s Server) configPath() string {
	if strings.TrimSpace(s.ConfigPath) != "" {
		return s.ConfigPath
	}
	return s.configDBPath()
}

func (s Server) configDBPath() string {
	if strings.TrimSpace(s.ConfigDBPath) != "" {
		return s.ConfigDBPath
	}
	return config.DefaultLocalDBPath
}

func (s Server) currentInstallConfig() config.Config {
	if s.LocalDB != nil {
		if cfg, ok, err := s.LocalDB.LoadConfig(context.Background()); err == nil && ok {
			return installConfigWithDockerDefaults(installConfigWithDefaults(cfg))
		}
	}
	cfg, _, _, _, _, _, _, _ := s.runtimeSnapshot()
	if strings.TrimSpace(cfg.AdminUsername) != "" || strings.TrimSpace(cfg.RSS) != "" {
		return installConfigWithDockerDefaults(installConfigWithDefaults(cfg))
	}
	return installConfigWithDockerDefaults(installConfigWithDefaults(cfg))
}

func (s Server) installLockMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/") || strings.HasPrefix(r.URL.Path, "/api/install") {
			next.ServeHTTP(w, r)
			return
		}
		if s.installOnly() || !s.installed() {
			writeError(w, http.StatusLocked, errors.New("系统尚未安装，请先完成安装向导"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s Server) reloadRuntime(ctx context.Context, cfg config.Config) error {
	if proxy.Apply(cfg) {
		s.log().Info("proxy configuration enabled")
	}
	mysqlStore, err := store.OpenMySQL(ctx, cfg)
	if err != nil {
		return err
	}
	redisCache, err := cache.OpenRedis(ctx, cfg)
	if err != nil {
		if mysqlStore != nil {
			_ = mysqlStore.Close()
		}
		return err
	}
	pp, provider, err := buildWebStorageProvider(cfg, proxy.HTTPClient())
	if err != nil {
		if mysqlStore != nil {
			_ = mysqlStore.Close()
		}
		if redisCache != nil {
			_ = redisCache.Close()
		}
		return err
	}
	if s.Runtime == nil {
		s.Runtime = NewRuntimeState(cfg, true, false, proxy.HTTPClient(), pp, provider, mysqlStore, redisCache)
		if s.Sessions != nil {
			s.Sessions.SetRedis(redisCache)
		}
		return nil
	}
	s.Runtime.Update(cfg, true, false, proxy.HTTPClient(), pp, provider, mysqlStore, redisCache)
	if s.Sessions != nil {
		s.Sessions.SetRedis(redisCache)
	}
	return nil
}

func buildWebStorageProvider(cfg config.Config, hc *http.Client) (PikPakClient, storage.Provider, error) {
	switch cfg.NormalizedStorageProvider() {
	case "pikpak":
		api, err := pikpak.NewGoAPIWithAuth(pikpak.AuthConfig{
			Username:     cfg.Username,
			Password:     cfg.Password,
			AuthMode:     cfg.PikPakAuthMode,
			AccessToken:  cfg.PikPakAccessToken,
			RefreshToken: cfg.PikPakRefreshToken,
			EncodedToken: cfg.PikPakEncodedToken,
		})
		if err != nil {
			return nil, nil, err
		}
		pp := pikpak.NewAdapter(api)
		return pp, storage.NewPikPakProvider(pp, cfg.Path), nil
	case "drive115":
		return nil, storage.NewDrive115Provider(cfg.Drive115Cookie, cfg.Drive115RootCID, hc), nil
	case "local":
		return nil, storage.NewAria2LocalProvider(cfg.LocalStoragePath, cfg.Aria2RPCURL, cfg.Aria2RPCSecret, hc), nil
	case "nas":
		return nil, storage.NewAria2NASProvider(cfg.NASStoragePath, cfg.Aria2RPCURL, cfg.Aria2RPCSecret, hc), nil
	default:
		return nil, nil, fmt.Errorf("不支持的储存桶类型：%s", cfg.StorageProvider)
	}
}

func (s Server) runtimeSnapshot() (config.Config, bool, bool, *http.Client, PikPakClient, storage.Provider, *store.MySQLStore, *cache.RedisCache) {
	if s.Runtime != nil {
		return s.Runtime.Snapshot()
	}
	return s.Config, false, s.InstallOnly, s.HTTPClient, s.PikPak, s.Storage, s.Store, s.Cache
}

func (s Server) runtimeConfig() config.Config {
	cfg, _, _, _, _, _, _, _ := s.runtimeSnapshot()
	return cfg
}

func (s Server) installed() bool {
	_, installed, _, _, _, _, _, _ := s.runtimeSnapshot()
	if installed {
		return true
	}
	if s.LocalDB != nil {
		return s.LocalDB.Installed(context.Background())
	}
	return false
}

func (s Server) installOnly() bool {
	_, _, installOnly, _, _, _, _, _ := s.runtimeSnapshot()
	return installOnly
}

func (s Server) loginUser(ctx context.Context, username, password string) (config.User, bool, error) {
	username = strings.TrimSpace(username)
	isInstallAdmin := validAdminCredentials(s.currentInstallConfig(), username, password)
	if s.LocalDB != nil {
		user, ok, err := s.LocalDB.FindUser(ctx, username)
		if err != nil {
			return config.User{}, false, err
		}
		if ok {
			if !validUserCredentials(user, password) {
				return config.User{}, false, nil
			}
			role := config.NormalizeRole(user.Role)
			if isInstallAdmin {
				role = config.RoleAdmin
				if user.Role != config.RoleAdmin {
					if err := s.LocalDB.SaveUser(ctx, config.User{Username: user.Username, Password: user.Password, Role: config.RoleAdmin}); err != nil {
						return config.User{}, false, err
					}
				}
			}
			return config.User{Username: user.Username, Role: role}, true, nil
		}
	}
	if isInstallAdmin {
		return config.User{Username: username, Role: config.RoleAdmin}, true, nil
	}
	return config.User{}, false, nil
}

func (s Server) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/") ||
			strings.HasPrefix(r.URL.Path, "/api/install") ||
			strings.HasPrefix(r.URL.Path, "/api/auth/") {
			next.ServeHTTP(w, r)
			return
		}
		user, ok := s.authenticatedUser(r)
		if s.adminOnlyAPI(r) {
			if !ok {
				writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
				return
			}
			if user.Role != config.RoleAdmin {
				writeError(w, http.StatusForbidden, errors.New("需要管理员权限"))
				return
			}
			next.ServeHTTP(w, r)
			return
		}
		if !s.runtimeConfig().RequireLogin {
			next.ServeHTTP(w, r)
			return
		}
		if !ok {
			writeError(w, http.StatusUnauthorized, errors.New("请先登录"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s Server) adminOnlyAPI(r *http.Request) bool {
	if strings.HasPrefix(r.URL.Path, "/api/admin/") {
		return true
	}
	switch r.URL.Path {
	case "/api/download", "/api/sync", "/api/mikan/subscribe", "/api/users":
		return true
	case "/api/library":
		return r.URL.Query().Get("refresh") == "1"
	default:
		return false
	}
}

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

func (s Server) authenticatedUsername(r *http.Request) (string, bool) {
	user, ok := s.authenticatedUser(r)
	return user.Username, ok
}

func (s Server) log() *slog.Logger {
	if s.Logger != nil {
		return s.Logger
	}
	return slog.Default()
}

func (s Server) coverResolver() bangumi.Client {
	return bangumi.Client{HTTPClient: s.httpClient()}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"ok": false, "error": chineseErrorMessage(err)})
}

func chineseErrorMessage(err error) string {
	if err == nil {
		return "操作失败"
	}
	raw := strings.TrimSpace(err.Error())
	if raw == "" {
		return "操作失败"
	}
	if containsCJK(raw) {
		return raw
	}
	lower := strings.ToLower(raw)
	switch {
	case strings.Contains(lower, "method not allowed"):
		return "请求方法不允许"
	case strings.Contains(lower, "not authenticated"):
		return "请先登录"
	case strings.Contains(lower, "admin permission required"):
		return "需要管理员权限"
	case strings.Contains(lower, "invalid username or password"):
		return "用户名或密码错误"
	case strings.Contains(lower, "registration is disabled"):
		return "注册功能已关闭"
	case strings.Contains(lower, "username already exists"):
		return "用户名已存在"
	case strings.Contains(lower, "username is required"):
		return "用户名不能为空"
	case strings.Contains(lower, "password is required"):
		return "密码不能为空"
	case strings.Contains(lower, "current password"):
		return "当前密码错误"
	case strings.Contains(lower, "new password"):
		return "新密码无效"
	case strings.Contains(lower, "not match") || strings.Contains(lower, "不一致"):
		return "两次输入的新密码不一致"
	case strings.Contains(lower, "invite code is required"):
		return "邀请码不能为空"
	case strings.Contains(lower, "invalid invite code"):
		return "邀请码无效"
	case strings.Contains(lower, "invite code has been used"):
		return "邀请码已被使用"
	case strings.Contains(lower, "invite code has expired"):
		return "邀请码已过期"
	case strings.Contains(lower, "storage provider is not initialized"):
		return "储存桶未初始化"
	case strings.Contains(lower, "unsupported storage provider"):
		return "不支持的储存桶类型"
	case strings.Contains(lower, "title and torrent_url/magnet are required"):
		return "标题和 torrent 链接或 magnet 链接不能为空"
	case strings.Contains(lower, "title is required"):
		return "标题不能为空"
	case strings.Contains(lower, "id is required"):
		return "ID 不能为空"
	case strings.Contains(lower, "download request not found"):
		return "下载申请不存在"
	case strings.Contains(lower, "request status"):
		return "下载申请状态不允许当前操作"
	case strings.Contains(lower, "pikpak login") || strings.Contains(lower, "captcha"):
		return "PikPak 登录失败，请检查账号状态或稍后再试"
	case strings.Contains(lower, "create pikpak offline task") || strings.Contains(lower, "offline download"):
		return "提交 PikPak 离线下载失败"
	case strings.Contains(lower, "pikpak file id is empty"):
		return "PikPak 文件 ID 为空"
	case strings.Contains(lower, "list pikpak folder"):
		return "读取 PikPak 文件夹失败"
	case strings.Contains(lower, "mysql"):
		return "MySQL 操作失败"
	case strings.Contains(lower, "redis"):
		return "Redis 操作失败"
	case strings.Contains(lower, "mikan"):
		return "Mikan 请求失败"
	case strings.Contains(lower, "bangumi"):
		return "Bangumi.tv 请求失败"
	case strings.Contains(lower, "torrent"):
		return "种子文件处理失败"
	case strings.Contains(lower, "local config db"):
		return "本地配置数据库未初始化"
	case strings.Contains(lower, "parse") || strings.Contains(lower, "decode") || strings.Contains(lower, "unmarshal"):
		return "数据解析失败"
	case strings.Contains(lower, "marshal"):
		return "数据序列化失败"
	case strings.Contains(lower, "read"):
		return "读取数据失败"
	case strings.Contains(lower, "write") || strings.Contains(lower, "save"):
		return "保存数据失败"
	case strings.Contains(lower, "open"):
		return "打开资源失败"
	case strings.Contains(lower, "ping"):
		return "连接检测失败"
	case strings.Contains(lower, "not found"):
		return "资源不存在"
	case strings.Contains(lower, "required"):
		return "缺少必填参数"
	case strings.Contains(lower, "unsupported"):
		return "当前操作不支持"
	case strings.Contains(lower, "invalid"):
		return "参数无效"
	default:
		return "操作失败，请查看服务端日志"
	}
}

func storageProviderLabel(name string) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "pikpak":
		return "PikPak 网盘"
	case "drive115":
		return "115 网盘"
	case "local":
		return "本地存储"
	case "nas":
		return "NAS 存储"
	default:
		if strings.TrimSpace(name) == "" {
			return "储存桶"
		}
		return name
	}
}

func errorString(err error) string {
	if err == nil {
		return ""
	}
	return chineseErrorMessage(err)
}

func installConfigWithDefaults(cfg config.Config) config.Config {
	defaults := config.Default()
	if strings.TrimSpace(cfg.PikPakAuthMode) == "" {
		cfg.PikPakAuthMode = defaults.PikPakAuthMode
	}
	if strings.TrimSpace(cfg.HTTPProxy) == "" {
		cfg.HTTPProxy = defaults.HTTPProxy
	}
	if strings.TrimSpace(cfg.HTTPSProxy) == "" {
		cfg.HTTPSProxy = defaults.HTTPSProxy
	}
	if strings.TrimSpace(cfg.SocksProxy) == "" {
		cfg.SocksProxy = defaults.SocksProxy
	}
	if strings.TrimSpace(cfg.MySQLHost) == "" {
		cfg.MySQLHost = defaults.MySQLHost
	}
	if cfg.MySQLPort == 0 {
		cfg.MySQLPort = defaults.MySQLPort
	}
	if strings.TrimSpace(cfg.MySQLDatabase) == "" {
		cfg.MySQLDatabase = defaults.MySQLDatabase
	}
	if strings.TrimSpace(cfg.RedisAddr) == "" {
		cfg.RedisAddr = defaults.RedisAddr
	}
	if strings.TrimSpace(cfg.StorageProvider) == "" {
		cfg.StorageProvider = defaults.StorageProvider
	}
	if strings.TrimSpace(cfg.Drive115RootCID) == "" {
		cfg.Drive115RootCID = defaults.Drive115RootCID
	}
	if strings.TrimSpace(cfg.Aria2RPCURL) == "" {
		cfg.Aria2RPCURL = defaults.Aria2RPCURL
	}
	if strings.TrimSpace(cfg.LocalStoragePath) == "" {
		cfg.LocalStoragePath = defaults.LocalStoragePath
	}
	return cfg
}

func installConfigWithDockerDefaults(cfg config.Config) config.Config {
	if !dockerInstallMode() {
		return cfg
	}
	cfg.MySQLHost = envOr("ANIMEX_MYSQL_HOST", firstNonEmpty(cfg.MySQLHost, "mysql"))
	cfg.MySQLPort = envIntOr("ANIMEX_MYSQL_PORT", firstNonZero(cfg.MySQLPort, 3306))
	cfg.MySQLDatabase = envOr("ANIMEX_MYSQL_DATABASE", firstNonEmpty(cfg.MySQLDatabase, "animex"))
	cfg.MySQLUsername = envOr("ANIMEX_MYSQL_USERNAME", firstNonEmpty(cfg.MySQLUsername, "animex"))
	if password, err := envOrFile("ANIMEX_MYSQL_PASSWORD", "ANIMEX_MYSQL_PASSWORD_FILE"); err == nil && strings.TrimSpace(password) != "" {
		cfg.MySQLPassword = password
	}
	cfg.RedisAddr = envOr("ANIMEX_REDIS_ADDR", firstNonEmpty(cfg.RedisAddr, "redis:6379"))
	if password, err := envOrFile("ANIMEX_REDIS_PASSWORD", "ANIMEX_REDIS_PASSWORD_FILE"); err == nil && strings.TrimSpace(password) != "" {
		cfg.RedisPassword = password
	}
	cfg.RedisDB = envIntOr("ANIMEX_REDIS_DB", cfg.RedisDB)
	cfg.StorageProvider = firstNonEmpty(envOr("ANIMEX_STORAGE_PROVIDER", ""), cfg.StorageProvider, "local")
	if cfg.NormalizedStorageProvider() == "pikpak" && strings.TrimSpace(cfg.Path) == "" && strings.TrimSpace(cfg.Username) == "" && strings.TrimSpace(cfg.Password) == "" && !cfg.PikPakTokenConfigured() {
		cfg.StorageProvider = "local"
	}
	cfg.LocalStoragePath = envOr("ANIMEX_LOCAL_STORAGE_PATH", firstNonEmpty(cfg.LocalStoragePath, "downloads"))
	return installConfigWithDefaults(cfg)
}

func dockerInstallMode() bool {
	return envBoolOr("ANIMEX_DOCKER", false) || envBoolOr("ANIMEX_AUTO_INSTALL", false) || envBoolOr("ANIMEX_SKIP_DB_INSTALL_STEPS", false)
}

func envOr(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func envOrFile(envName, fileEnvName string) (string, error) {
	if value := strings.TrimSpace(os.Getenv(envName)); value != "" {
		return value, nil
	}
	filePath := strings.TrimSpace(os.Getenv(fileEnvName))
	if filePath == "" {
		return "", nil
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func envIntOr(name string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envBoolOr(name string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func firstNonZero(values ...int) int {
	for _, value := range values {
		if value != 0 {
			return value
		}
	}
	return 0
}

func testMySQLConnection(parent context.Context, cfg config.Config) error {
	if !cfg.MySQLConfigured() {
		return errors.New("MySQL 配置不完整")
	}
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	dsn := mysqlDSN(cfg)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return fmt.Errorf("打开 MySQL 失败：%w", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("连接 MySQL 失败：%w", err)
	}
	return nil
}

func mysqlDSN(cfg config.Config) string {
	if strings.TrimSpace(cfg.MySQLDSN) != "" {
		return strings.TrimSpace(cfg.MySQLDSN)
	}
	host := strings.TrimSpace(cfg.MySQLHost)
	if host == "" {
		host = "127.0.0.1"
	}
	port := cfg.MySQLPort
	if port == 0 {
		port = 3306
	}
	params := url.Values{}
	params.Set("charset", "utf8mb4")
	params.Set("parseTime", "true")
	params.Set("loc", "Local")
	return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?%s", cfg.MySQLUsername, cfg.MySQLPassword, host, port, cfg.MySQLDatabase, params.Encode())
}

func mergeInstallConfig(current, incoming config.Config) config.Config {
	incoming.Username = firstNonEmpty(incoming.Username, current.Username)
	incoming.Password = firstNonEmpty(incoming.Password, current.Password)
	incoming.PikPakAuthMode = firstNonEmpty(incoming.PikPakAuthMode, current.PikPakAuthMode, config.Default().PikPakAuthMode)
	incoming.PikPakAccessToken = firstNonEmpty(incoming.PikPakAccessToken, current.PikPakAccessToken)
	incoming.PikPakRefreshToken = firstNonEmpty(incoming.PikPakRefreshToken, current.PikPakRefreshToken)
	incoming.PikPakEncodedToken = firstNonEmpty(incoming.PikPakEncodedToken, current.PikPakEncodedToken)
	incoming.Path = firstNonEmpty(incoming.Path, current.Path)
	incoming.RSS = firstNonEmpty(incoming.RSS, current.RSS)
	incoming.MikanUsername = firstNonEmpty(incoming.MikanUsername, current.MikanUsername)
	incoming.MikanPassword = firstNonEmpty(incoming.MikanPassword, current.MikanPassword)
	incoming.StorageProvider = firstNonEmpty(incoming.StorageProvider, current.StorageProvider, config.Default().StorageProvider)
	incoming.Drive115Cookie = firstNonEmpty(incoming.Drive115Cookie, current.Drive115Cookie)
	incoming.Drive115RootCID = firstNonEmpty(incoming.Drive115RootCID, current.Drive115RootCID, config.Default().Drive115RootCID)
	incoming.Aria2RPCURL = firstNonEmpty(incoming.Aria2RPCURL, current.Aria2RPCURL, config.Default().Aria2RPCURL)
	incoming.Aria2RPCSecret = firstNonEmpty(incoming.Aria2RPCSecret, current.Aria2RPCSecret)
	incoming.LocalStoragePath = firstNonEmpty(incoming.LocalStoragePath, current.LocalStoragePath, config.Default().LocalStoragePath)
	incoming.NASStoragePath = firstNonEmpty(incoming.NASStoragePath, current.NASStoragePath)
	// 安装页暂不暴露该项，默认要求登录；后台系统配置可关闭。
	if !incoming.RequireLogin && !current.RequireLogin {
		incoming.RequireLogin = false
	} else {
		incoming.RequireLogin = true
	}
	if current.EnableRegistration {
		incoming.EnableRegistration = true
	}
	incoming.RequireInvite = current.RequireInvite
	incoming.AdminUsername = firstNonEmpty(incoming.AdminUsername, current.AdminUsername, config.Default().AdminUsername)
	incoming.AdminPassword = firstNonEmpty(incoming.AdminPassword, current.AdminPassword)
	return installConfigWithDefaults(incoming)
}

func normalizeInstallStorage(cfg config.Config) config.Config {
	cfg = installConfigWithDefaults(cfg)
	switch cfg.NormalizedStorageProvider() {
	case "pikpak":
		if strings.TrimSpace(cfg.Path) == "" && !cfg.PikPakTokenConfigured() && (strings.TrimSpace(cfg.Username) == "" || strings.TrimSpace(cfg.Password) == "") {
			cfg.StorageProvider = "local"
			cfg.LocalStoragePath = firstNonEmpty(cfg.LocalStoragePath, config.Default().LocalStoragePath)
		}
	case "drive115":
		if strings.TrimSpace(cfg.Drive115Cookie) == "" {
			cfg.StorageProvider = "local"
			cfg.LocalStoragePath = firstNonEmpty(cfg.LocalStoragePath, config.Default().LocalStoragePath)
		}
	case "nas":
		if strings.TrimSpace(cfg.NASStoragePath) == "" {
			cfg.StorageProvider = "local"
			cfg.LocalStoragePath = firstNonEmpty(cfg.LocalStoragePath, config.Default().LocalStoragePath)
		}
	}
	return installConfigWithDefaults(cfg)
}

func loggingMiddleware(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		if strings.HasPrefix(r.URL.Path, "/api/") {
			log.Info("web request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start).String())
		}
	})
}
