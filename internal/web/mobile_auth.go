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
