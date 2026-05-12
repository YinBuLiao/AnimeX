package main

import (
	"context"
	"crypto/rand"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"bangumi-pikpak/internal/app"
	"bangumi-pikpak/internal/cache"
	"bangumi-pikpak/internal/config"
	"bangumi-pikpak/internal/logger"
	"bangumi-pikpak/internal/pikpak"
	"bangumi-pikpak/internal/proxy"
	"bangumi-pikpak/internal/storage"
	"bangumi-pikpak/internal/store"
	"bangumi-pikpak/internal/web"
)

const appVersion = "dev"

func main() {
	configDBPath := flag.String("configdb", config.DefaultLocalDBPath, "path to local SQLite config database")
	intervalSeconds := flag.Int("interval", 600, "RSS polling interval in seconds")
	once := flag.Bool("once", false, "run one sync cycle and exit")
	webMode := flag.Bool("web", true, "serve the Vue web UI by default; set -web=false for CLI-only sync")
	addr := flag.String("addr", ":8080", "web UI listen address")
	staticDir := flag.String("static", "frontend/dist", "Vue web UI dist directory")
	logFile := flag.String("log", "", "optional log file path; empty means console only")
	statePath := flag.String("state", "", "deprecated legacy PikPak state file path used only for one-time import")
	flag.Parse()

	log := logger.New(*logFile)
	slog.SetDefault(log)

	localDB, err := config.OpenLocalDB(*configDBPath)
	if err != nil {
		log.Error("open local config db failed", "error", err)
		os.Exit(1)
	}
	defer localDB.Close()

	cfg := config.Default()
	installed := localDB.Installed(context.Background())
	dbCfg, hasDBConfig, loadDBErr := localDB.LoadConfig(context.Background())
	if loadDBErr != nil {
		log.Warn("load local db config failed, start install wizard", "configdb", *configDBPath, "error", loadDBErr)
	} else if hasDBConfig {
		cfg = dbCfg
	}
	if shouldAutoInstall() && (!installed || !hasDBConfig) {
		autoCfg, err := dockerAutoInstallConfig(cfg)
		if err != nil {
			log.Error("docker auto install config failed", "error", err)
			os.Exit(1)
		}
		if err := autoCfg.ValidateInstall(); err != nil {
			log.Error("docker auto install config is incomplete", "error", err)
			os.Exit(1)
		}
		if err := localDB.SaveConfig(context.Background(), autoCfg); err != nil {
			log.Error("docker auto install failed", "error", err)
			os.Exit(1)
		}
		cfg = autoCfg
		installed = true
		hasDBConfig = true
		log.Info("docker auto install completed", "configdb", *configDBPath, "admin_username", cfg.AdminUsername, "mysql_host", cfg.MySQLHost, "redis_addr", cfg.RedisAddr, "storage_provider", cfg.NormalizedStorageProvider())
	}
	if !installed || !hasDBConfig || cfg.ValidateInstall() != nil {
		if *webMode {
			ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
			defer stop()
			webServer := web.Server{Config: cfg, ConfigDBPath: *configDBPath, LocalDB: localDB, InstallOnly: true, HTTPClient: http.DefaultClient, Logger: log, TorrentRoot: "torrent", StaticDir: *staticDir, Version: appVersion}
			httpServer := &http.Server{Addr: *addr, Handler: webServer.Handler()}
			errCh := make(chan error, 1)
			go func() {
				log.Warn("web install wizard listening", "addr", *addr, "installed", installed)
				if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
					errCh <- err
				}
			}()
			select {
			case <-ctx.Done():
				log.Info("shutdown requested")
			case err := <-errCh:
				log.Error("web install wizard failed", "error", err)
			}
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			if err := httpServer.Shutdown(shutdownCtx); err != nil {
				log.Error("web install wizard shutdown failed", "error", err)
				os.Exit(1)
			}
			return
		}
		log.Error("system is not installed")
		os.Exit(1)
	}
	if proxy.Apply(cfg) {
		log.Info("proxy configuration enabled")
	}

	mysqlStore, err := store.OpenMySQL(context.Background(), cfg)
	if err != nil {
		log.Error("mysql initialization failed", "error", err)
		os.Exit(1)
	}
	if mysqlStore != nil {
		defer mysqlStore.Close()
		log.Info("mysql state management enabled", "database", cfg.MySQLDatabase)
	}
	redisCache, err := cache.OpenRedis(context.Background(), cfg)
	if err != nil {
		log.Warn("redis initialization failed, continue without redis cache", "error", err)
	}
	if redisCache != nil {
		defer redisCache.Close()
		log.Info("redis cache enabled", "addr", cfg.RedisAddr, "ttl", "15m")
	}

	pp, storageProvider, err := buildRuntimeStorage(cfg, *statePath, localDB, log)
	if err != nil {
		log.Error("create storage provider failed", "provider", cfg.NormalizedStorageProvider(), "error", err)
		os.Exit(1)
	}
	runner := app.Runner{Config: cfg, HTTPClient: proxy.HTTPClient(), Logger: log, TorrentRoot: "torrent", PikPak: pp, Storage: storageProvider, Store: mysqlStore}
	scheduler := &syncScheduler{runner: runner, log: log}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if *webMode {
		webServer := web.Server{Config: cfg, ConfigDBPath: *configDBPath, LocalDB: localDB, HTTPClient: proxy.HTTPClient(), Logger: log, TorrentRoot: "torrent", StaticDir: *staticDir, PikPak: pp, Storage: storageProvider, Store: mysqlStore, Cache: redisCache, Version: appVersion}
		httpServer := &http.Server{Addr: *addr, Handler: webServer.Handler()}
		errCh := make(chan error, 1)
		go func() {
			log.Info("web UI listening", "addr", *addr)
			if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				errCh <- err
			}
		}()
		if !*once && strings.TrimSpace(cfg.RSS) != "" {
			interval := time.Duration(*intervalSeconds) * time.Second
			go scheduler.Loop(ctx, interval, 15*time.Second)
		} else if strings.TrimSpace(cfg.RSS) == "" {
			log.Info("RSS scheduler disabled because RSS is not configured")
		}
		select {
		case <-ctx.Done():
			log.Info("shutdown requested")
		case err := <-errCh:
			log.Error("web UI server failed", "error", err)
		}
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			log.Error("web UI shutdown failed", "error", err)
			os.Exit(1)
		}
		return
	}

	if *once {
		if !scheduler.Run(ctx) {
			os.Exit(1)
		}
		return
	}

	interval := time.Duration(*intervalSeconds) * time.Second
	scheduler.Loop(ctx, interval, 0)
}

type syncScheduler struct {
	mu      sync.Mutex
	running bool
	runner  app.Runner
	log     *slog.Logger
}

func (s *syncScheduler) Run(ctx context.Context) bool {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		s.log.Info("skip RSS sync because previous cycle is still running")
		return true
	}
	s.running = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.running = false
		s.mu.Unlock()
	}()

	if err := s.runner.RunOnce(ctx); err != nil {
		s.log.Error("sync cycle failed", "error", err)
		return false
	}
	return true
}

func (s *syncScheduler) Loop(ctx context.Context, interval, initialDelay time.Duration) {
	if initialDelay > 0 {
		s.log.Info("RSS sync scheduled after web startup", "initial_delay", initialDelay.String(), "interval", interval.String())
		select {
		case <-ctx.Done():
			return
		case <-time.After(initialDelay):
		}
	}
	for {
		s.Run(ctx)
		select {
		case <-ctx.Done():
			s.log.Info("RSS scheduler stopped")
			return
		case <-time.After(interval):
		}
	}
}

func buildRuntimeStorage(cfg config.Config, legacyStatePath string, localDB *config.LocalDB, log *slog.Logger) (*lockedPikPak, storage.Provider, error) {
	switch cfg.NormalizedStorageProvider() {
	case "pikpak":
		auth := pikpak.AuthConfig{
			Username:     cfg.Username,
			Password:     cfg.Password,
			AuthMode:     cfg.PikPakAuthMode,
			AccessToken:  cfg.PikPakAccessToken,
			RefreshToken: cfg.PikPakRefreshToken,
			EncodedToken: cfg.PikPakEncodedToken,
		}
		if strings.TrimSpace(auth.AccessToken) == "" && strings.TrimSpace(auth.RefreshToken) == "" && strings.TrimSpace(auth.EncodedToken) == "" {
			if state, ok, err := loadPikPakStateFromDB(localDB); err == nil && ok && strings.TrimSpace(state.RefreshToken) != "" {
				auth.AccessToken = state.AccessToken
				auth.RefreshToken = state.RefreshToken
				log.Info("loaded pikpak token from local db", "username", state.Username)
			} else if err != nil {
				log.Warn("load pikpak state from local db failed, continue with configured auth", "error", err)
			} else if state, migrated, err := migrateLegacyPikPakState(localDB, legacyStatePath, log); err == nil && migrated && strings.TrimSpace(state.RefreshToken) != "" {
				auth.AccessToken = state.AccessToken
				auth.RefreshToken = state.RefreshToken
				log.Info("loaded pikpak token from migrated local db state", "username", state.Username)
			} else if err != nil {
				log.Warn("migrate legacy pikpak state failed, continue with configured auth", "error", err)
			}
		}
		api, err := pikpak.NewGoAPIWithAuth(auth)
		if err != nil {
			return nil, nil, err
		}
		pp := &lockedPikPak{inner: pikpak.NewAdapter(api), localDB: localDB, username: cfg.Username, log: log}
		return pp, storage.NewPikPakProvider(pp, cfg.Path), nil
	case "drive115":
		return nil, storage.NewDrive115Provider(cfg.Drive115Cookie, cfg.Drive115RootCID, proxy.HTTPClient()), nil
	case "local":
		return nil, storage.NewAria2LocalProvider(cfg.LocalStoragePath, cfg.Aria2RPCURL, cfg.Aria2RPCSecret, proxy.HTTPClient()), nil
	case "nas":
		return nil, storage.NewAria2NASProvider(cfg.NASStoragePath, cfg.Aria2RPCURL, cfg.Aria2RPCSecret, proxy.HTTPClient()), nil
	default:
		return nil, nil, errors.New("unsupported storage provider: " + cfg.StorageProvider)
	}
}

func shouldAutoInstall() bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv("ANIMEX_AUTO_INSTALL")))
	return value == "1" || value == "true" || value == "yes" || value == "on"
}

func dockerAutoInstallConfig(base config.Config) (config.Config, error) {
	cfg := base
	defaults := config.Default()
	cfg.AdminUsername = envOr("ANIMEX_ADMIN_USERNAME", firstNonEmptyString(cfg.AdminUsername, defaults.AdminUsername))
	adminPassword, err := envOrFile("ANIMEX_ADMIN_PASSWORD", "ANIMEX_ADMIN_PASSWORD_FILE")
	if err != nil {
		return config.Config{}, err
	}
	if strings.TrimSpace(adminPassword) == "" {
		adminPassword = randomSecret(24)
	}
	cfg.AdminPassword = adminPassword

	cfg.MySQLHost = envOr("ANIMEX_MYSQL_HOST", firstNonEmptyString(cfg.MySQLHost, "mysql"))
	cfg.MySQLPort = envIntOr("ANIMEX_MYSQL_PORT", firstNonZeroInt(cfg.MySQLPort, 3306))
	cfg.MySQLDatabase = envOr("ANIMEX_MYSQL_DATABASE", firstNonEmptyString(cfg.MySQLDatabase, "animex"))
	cfg.MySQLUsername = envOr("ANIMEX_MYSQL_USERNAME", firstNonEmptyString(cfg.MySQLUsername, "animex"))
	mysqlPassword, err := envOrFile("ANIMEX_MYSQL_PASSWORD", "ANIMEX_MYSQL_PASSWORD_FILE")
	if err != nil {
		return config.Config{}, err
	}
	cfg.MySQLPassword = firstNonEmptyString(mysqlPassword, cfg.MySQLPassword)
	cfg.MySQLDSN = envOr("ANIMEX_MYSQL_DSN", cfg.MySQLDSN)

	cfg.RedisAddr = envOr("ANIMEX_REDIS_ADDR", firstNonEmptyString(cfg.RedisAddr, "redis:6379"))
	redisPassword, err := envOrFile("ANIMEX_REDIS_PASSWORD", "ANIMEX_REDIS_PASSWORD_FILE")
	if err != nil {
		return config.Config{}, err
	}
	cfg.RedisPassword = firstNonEmptyString(redisPassword, cfg.RedisPassword)
	cfg.RedisDB = envIntOr("ANIMEX_REDIS_DB", cfg.RedisDB)

	cfg.RequireLogin = envBoolOr("ANIMEX_REQUIRE_LOGIN", cfg.RequireLogin)
	cfg.EnableRegistration = envBoolOr("ANIMEX_ENABLE_REGISTRATION", cfg.EnableRegistration)
	cfg.RequireInvite = envBoolOr("ANIMEX_REQUIRE_INVITE", cfg.RequireInvite)
	cfg.UserDailyDownloadLimit = envIntOr("ANIMEX_USER_DAILY_DOWNLOAD_LIMIT", firstNonZeroInt(cfg.UserDailyDownloadLimit, defaults.UserDailyDownloadLimit))

	cfg.StorageProvider = envOr("ANIMEX_STORAGE_PROVIDER", firstNonEmptyString(cfg.StorageProvider, "local"))
	if strings.TrimSpace(cfg.StorageProvider) == "" || cfg.NormalizedStorageProvider() == "pikpak" {
		if strings.TrimSpace(cfg.Path) == "" && strings.TrimSpace(cfg.Username) == "" && strings.TrimSpace(cfg.Password) == "" && !cfg.PikPakTokenConfigured() {
			cfg.StorageProvider = "local"
		}
	}
	cfg.Aria2RPCURL = envOr("ANIMEX_ARIA2_RPC_URL", firstNonEmptyString(cfg.Aria2RPCURL, defaults.Aria2RPCURL))
	cfg.Aria2RPCSecret = envOr("ANIMEX_ARIA2_RPC_SECRET", cfg.Aria2RPCSecret)
	cfg.LocalStoragePath = envOr("ANIMEX_LOCAL_STORAGE_PATH", firstNonEmptyString(cfg.LocalStoragePath, defaults.LocalStoragePath))
	cfg.NASStoragePath = envOr("ANIMEX_NAS_STORAGE_PATH", cfg.NASStoragePath)
	cfg.RSS = envOr("ANIMEX_RSS", cfg.RSS)
	return cfg, nil
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

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func firstNonZeroInt(values ...int) int {
	for _, value := range values {
		if value != 0 {
			return value
		}
	}
	return 0
}

func randomSecret(length int) string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	if length <= 0 {
		length = 24
	}
	buf := make([]byte, length)
	if _, err := rand.Read(buf); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	for i, b := range buf {
		buf[i] = chars[int(b)%len(chars)]
	}
	return string(buf)
}

func loadPikPakStateFromDB(localDB *config.LocalDB) (config.PikPakState, bool, error) {
	if localDB == nil {
		return config.PikPakState{}, false, nil
	}
	return localDB.LoadPikPakState(context.Background())
}

func migrateLegacyPikPakState(localDB *config.LocalDB, legacyStatePath string, log *slog.Logger) (config.PikPakState, bool, error) {
	if localDB == nil {
		return config.PikPakState{}, false, nil
	}
	legacyStatePath = strings.TrimSpace(legacyStatePath)
	if legacyStatePath == "" {
		legacyStatePath = "pikpak" + ".json"
	}
	state, err := pikpak.LoadState(legacyStatePath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return config.PikPakState{}, false, nil
		}
		return config.PikPakState{}, false, err
	}
	dbState := config.PikPakState{
		Username:        state.Username,
		LastLoginTime:   state.LastLoginTime,
		LastRefreshTime: state.LastRefreshTime,
		Client:          state.Client,
		AccessToken:     state.AccessToken,
		RefreshToken:    state.RefreshToken,
	}
	if err := localDB.SavePikPakState(context.Background(), dbState); err != nil {
		return config.PikPakState{}, false, err
	}
	if err := os.Remove(legacyStatePath); err != nil && !errors.Is(err, os.ErrNotExist) && log != nil {
		log.Warn("remove legacy pikpak state file failed", "state", legacyStatePath, "error", err)
	}
	return dbState, true, nil
}

type lockedPikPak struct {
	mu        sync.Mutex
	inner     *pikpak.Adapter
	lastLogin time.Time
	localDB   *config.LocalDB
	username  string
	log       *slog.Logger
}

func (l *lockedPikPak) Login() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if !l.lastLogin.IsZero() && time.Since(l.lastLogin) < 20*time.Minute {
		return nil
	}
	if err := l.inner.Login(); err != nil {
		return err
	}
	l.lastLogin = time.Now()
	l.saveTokenStateLocked()
	return nil
}

func (l *lockedPikPak) EnsureFolder(parentID, name string) (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	id, err := l.inner.EnsureFolder(parentID, name)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return id, err
}

func (l *lockedPikPak) HasOriginalURL(parentID, targetURL string) (bool, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	ok, err := l.inner.HasOriginalURL(parentID, targetURL)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return ok, err
}

func (l *lockedPikPak) HasChildren(parentID string) (bool, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	ok, err := l.inner.HasChildren(parentID)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return ok, err
}

func (l *lockedPikPak) OfflineDownload(name, fileURL, parentID string) (pikpak.RemoteTask, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	task, err := l.inner.OfflineDownload(name, fileURL, parentID)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return task, err
}

func (l *lockedPikPak) DeleteFile(id string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	err := l.inner.DeleteFile(id)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return err
}

func (l *lockedPikPak) List(parentID string) ([]pikpak.RemoteFile, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	files, err := l.inner.List(parentID)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return files, err
}

func (l *lockedPikPak) DownloadURL(id string) (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	u, err := l.inner.DownloadURL(id)
	if err == nil {
		l.saveTokenStateLocked()
	}
	return u, err
}

func (l *lockedPikPak) saveTokenStateLocked() {
	tokens := l.inner.Tokens()
	if strings.TrimSpace(tokens.AccessToken) == "" || strings.TrimSpace(tokens.RefreshToken) == "" || l.localDB == nil {
		return
	}
	state := config.PikPakState{
		Username:        l.username,
		LastLoginTime:   l.lastLogin,
		LastRefreshTime: time.Now(),
		Client:          "pikpak-go",
		AccessToken:     tokens.AccessToken,
		RefreshToken:    tokens.RefreshToken,
	}
	if err := l.localDB.SavePikPakState(context.Background(), state); err != nil {
		if l.log != nil {
			l.log.Warn("save pikpak token state to local db failed", "error", err)
		}
	}
}
