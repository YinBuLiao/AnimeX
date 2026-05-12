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
		"installed": s.installed(),
	})
}
