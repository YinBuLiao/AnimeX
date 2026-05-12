package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"

	"bangumi-pikpak/internal/config"

	_ "github.com/go-sql-driver/mysql"
)

type MySQLStore struct {
	db *sql.DB
}

type BangumiRecord struct {
	Title            string
	PikPakFolderID   string
	CoverURL         string
	Summary          string
	BangumiSubjectID int
	MikanBangumiID   int
	Subscribed       bool
}

type Snapshot struct {
	Key       string
	Payload   []byte
	UpdatedAt time.Time
}

func OpenMySQL(ctx context.Context, cfg config.Config) (*MySQLStore, error) {
	if !cfg.MySQLConfigured() {
		return nil, nil
	}
	dsn := strings.TrimSpace(cfg.MySQLDSN)
	if dsn == "" {
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
		dsn = fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?%s", cfg.MySQLUsername, cfg.MySQLPassword, host, port, cfg.MySQLDatabase, params.Encode())
	}
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("open mysql: %w", err)
	}
	db.SetMaxOpenConns(8)
	db.SetMaxIdleConns(4)
	db.SetConnMaxLifetime(30 * time.Minute)
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping mysql: %w", err)
	}
	s := &MySQLStore{db: db}
	if err := s.EnsureSchema(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *MySQLStore) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *MySQLStore) EnsureSchema(ctx context.Context) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS bangumi (
			id BIGINT PRIMARY KEY AUTO_INCREMENT,
			title VARCHAR(512) NOT NULL,
			pikpak_folder_id VARCHAR(128) NOT NULL DEFAULT '',
			cover_url TEXT NULL,
			summary TEXT NULL,
			bangumi_subject_id BIGINT NOT NULL DEFAULT 0,
			mikan_bangumi_id BIGINT NOT NULL DEFAULT 0,
			subscribed TINYINT(1) NOT NULL DEFAULT 0,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			UNIQUE KEY uq_bangumi_title (title),
			KEY idx_pikpak_folder_id (pikpak_folder_id),
			KEY idx_bangumi_subject_id (bangumi_subject_id),
			KEY idx_mikan_bangumi_id (mikan_bangumi_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS episodes (
			id BIGINT PRIMARY KEY AUTO_INCREMENT,
			bangumi_id BIGINT NOT NULL,
			label VARCHAR(128) NOT NULL,
			pikpak_folder_id VARCHAR(128) NOT NULL DEFAULT '',
			torrent_url TEXT NULL,
			downloaded_at TIMESTAMP NULL,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			UNIQUE KEY uq_episode (bangumi_id, label),
			CONSTRAINT fk_episodes_bangumi FOREIGN KEY (bangumi_id) REFERENCES bangumi(id) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS subscriptions (
			id BIGINT PRIMARY KEY AUTO_INCREMENT,
			bangumi_id BIGINT NOT NULL,
			language INT NOT NULL DEFAULT 0,
			source VARCHAR(32) NOT NULL DEFAULT 'mikan',
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			UNIQUE KEY uq_subscription (bangumi_id, source),
			CONSTRAINT fk_subscriptions_bangumi FOREIGN KEY (bangumi_id) REFERENCES bangumi(id) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS cache_snapshots (
			cache_key VARCHAR(128) PRIMARY KEY,
			payload LONGTEXT NOT NULL,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
	}
	for _, stmt := range stmts {
		if _, err := s.db.ExecContext(ctx, stmt); err != nil {
			return fmt.Errorf("ensure mysql schema: %w", err)
		}
	}
	return nil
}

func (s *MySQLStore) UpsertBangumi(ctx context.Context, rec BangumiRecord) error {
	if s == nil {
		return nil
	}
	title := strings.TrimSpace(rec.Title)
	if title == "" {
		return nil
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO bangumi (title, pikpak_folder_id, cover_url, summary, bangumi_subject_id, mikan_bangumi_id, subscribed)
		VALUES (?, ?, NULLIF(?, ''), NULLIF(?, ''), ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			pikpak_folder_id = IF(VALUES(pikpak_folder_id) <> '', VALUES(pikpak_folder_id), pikpak_folder_id),
			cover_url = IF(VALUES(cover_url) IS NOT NULL, VALUES(cover_url), cover_url),
			summary = IF(VALUES(summary) IS NOT NULL, VALUES(summary), summary),
			bangumi_subject_id = IF(VALUES(bangumi_subject_id) <> 0, VALUES(bangumi_subject_id), bangumi_subject_id),
			mikan_bangumi_id = IF(VALUES(mikan_bangumi_id) <> 0, VALUES(mikan_bangumi_id), mikan_bangumi_id),
			subscribed = IF(VALUES(subscribed) = 1, 1, subscribed)`,
		title, rec.PikPakFolderID, rec.CoverURL, rec.Summary, rec.BangumiSubjectID, rec.MikanBangumiID, rec.Subscribed)
	return err
}

func (s *MySQLStore) Metadata(ctx context.Context, title string) (BangumiRecord, bool, error) {
	if s == nil || strings.TrimSpace(title) == "" {
		return BangumiRecord{}, false, nil
	}
	var rec BangumiRecord
	err := s.db.QueryRowContext(ctx, `SELECT title, pikpak_folder_id, COALESCE(cover_url,''), COALESCE(summary,''), bangumi_subject_id, mikan_bangumi_id, subscribed FROM bangumi WHERE title = ?`, strings.TrimSpace(title)).Scan(&rec.Title, &rec.PikPakFolderID, &rec.CoverURL, &rec.Summary, &rec.BangumiSubjectID, &rec.MikanBangumiID, &rec.Subscribed)
	if err == sql.ErrNoRows {
		return BangumiRecord{}, false, nil
	}
	if err != nil {
		return BangumiRecord{}, false, err
	}
	return rec, true, nil
}

func (s *MySQLStore) EpisodeProcessed(ctx context.Context, title, label string) (bool, error) {
	if s == nil {
		return false, nil
	}
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM episodes e JOIN bangumi b ON b.id=e.bangumi_id WHERE b.title=? AND e.label=? AND e.downloaded_at IS NOT NULL`, strings.TrimSpace(title), strings.TrimSpace(label)).Scan(&n)
	return n > 0, err
}

func (s *MySQLStore) MarkEpisodeDownloaded(ctx context.Context, title, label, folderID, torrentURL string) error {
	if s == nil {
		return nil
	}
	if err := s.UpsertBangumi(ctx, BangumiRecord{Title: title}); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO episodes (bangumi_id, label, pikpak_folder_id, torrent_url, downloaded_at)
		SELECT id, ?, ?, NULLIF(?, ''), NOW() FROM bangumi WHERE title=?
		ON DUPLICATE KEY UPDATE
			episodes.pikpak_folder_id=IF(VALUES(pikpak_folder_id)<>'',VALUES(pikpak_folder_id),episodes.pikpak_folder_id),
			episodes.torrent_url=IF(VALUES(torrent_url) IS NOT NULL,VALUES(torrent_url),episodes.torrent_url),
			episodes.downloaded_at=NOW()`, strings.TrimSpace(label), strings.TrimSpace(folderID), strings.TrimSpace(torrentURL), strings.TrimSpace(title))
	return err
}

func (s *MySQLStore) SaveBangumiMetadata(ctx context.Context, title, coverURL, summary string) error {
	return s.UpsertBangumi(ctx, BangumiRecord{Title: title, CoverURL: coverURL, Summary: summary})
}

func (s *MySQLStore) DeleteBangumi(ctx context.Context, titles []string) (int64, error) {
	if s == nil || len(titles) == 0 {
		return 0, nil
	}
	cleaned := make([]string, 0, len(titles))
	for _, title := range titles {
		if title = strings.TrimSpace(title); title != "" {
			cleaned = append(cleaned, title)
		}
	}
	if len(cleaned) == 0 {
		return 0, nil
	}
	placeholders := strings.TrimRight(strings.Repeat("?,", len(cleaned)), ",")
	args := make([]any, 0, len(cleaned))
	for _, title := range cleaned {
		args = append(args, title)
	}
	res, err := s.db.ExecContext(ctx, `DELETE FROM bangumi WHERE title IN (`+placeholders+`)`, args...)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func (s *MySQLStore) DeleteEpisode(ctx context.Context, title, label string) (int64, error) {
	if s == nil {
		return 0, nil
	}
	title = strings.TrimSpace(title)
	label = strings.TrimSpace(label)
	if title == "" || label == "" {
		return 0, nil
	}
	res, err := s.db.ExecContext(ctx, `DELETE e FROM episodes e JOIN bangumi b ON b.id=e.bangumi_id WHERE b.title=? AND e.label=?`, title, label)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

func (s *MySQLStore) SaveSubscription(ctx context.Context, rec BangumiRecord, language int) error {
	if s == nil {
		return nil
	}
	rec.Subscribed = true
	if err := s.UpsertBangumi(ctx, rec); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO subscriptions (bangumi_id, language, source)
		SELECT id, ?, 'mikan' FROM bangumi WHERE title=?
		ON DUPLICATE KEY UPDATE language=VALUES(language)`, language, strings.TrimSpace(rec.Title))
	return err
}

// ListSubscribedTitles returns the titles of every bangumi flagged
// subscribed. The mobile client calls this on login to hydrate its local
// SubscribedStore so the 已订阅 button is stable across devices.
func (s *MySQLStore) ListSubscribedTitles(ctx context.Context) ([]string, error) {
	if s == nil {
		return nil, nil
	}
	rows, err := s.db.QueryContext(ctx, `SELECT title FROM bangumi WHERE subscribed = 1 ORDER BY title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *MySQLStore) SaveSnapshot(ctx context.Context, key string, value any) error {
	if s == nil || strings.TrimSpace(key) == "" {
		return nil
	}
	payload, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal mysql snapshot: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO cache_snapshots (cache_key, payload, updated_at) VALUES (?, ?, NOW())
		ON DUPLICATE KEY UPDATE payload=VALUES(payload), updated_at=NOW()`, strings.TrimSpace(key), string(payload))
	return err
}

func (s *MySQLStore) LoadSnapshot(ctx context.Context, key string, target any) (time.Time, bool, error) {
	if s == nil || strings.TrimSpace(key) == "" {
		return time.Time{}, false, nil
	}
	var payload string
	var updatedAt time.Time
	err := s.db.QueryRowContext(ctx, `SELECT payload, updated_at FROM cache_snapshots WHERE cache_key=?`, strings.TrimSpace(key)).Scan(&payload, &updatedAt)
	if err == sql.ErrNoRows {
		return time.Time{}, false, nil
	}
	if err != nil {
		return time.Time{}, false, err
	}
	if err := json.Unmarshal([]byte(payload), target); err != nil {
		return time.Time{}, false, fmt.Errorf("parse mysql snapshot: %w", err)
	}
	return updatedAt, true, nil
}
