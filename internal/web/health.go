package web

import (
	"errors"
	"net/http"
	"strings"
)

func (s Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeError(w, http.StatusMethodNotAllowed, errors.New("请求方法不允许"))
		return
	}
	cfg := s.runtimeConfig()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":                true,
		"version":           s.Version,
		"installed":         s.installed(),
		"mikan_configured":  cfg.MikanConfigured(),
		"mysql_ready":       s.store() != nil,
		"pikpak_configured": cfg.PikPakTokenConfigured() ||
			(strings.TrimSpace(cfg.Username) != "" && strings.TrimSpace(cfg.Password) != ""),
		"storage_provider": cfg.NormalizedStorageProvider(),
	})
}
