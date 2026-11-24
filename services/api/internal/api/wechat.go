package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

const wechatPlaceholderAppID = "touristappid"

var devUserID = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

func (s *Server) wechatReady() bool {
	id := strings.TrimSpace(s.WechatAppID)
	secret := strings.TrimSpace(s.WechatAppSecret)
	return id != "" && secret != "" && id != wechatPlaceholderAppID
}

func (s *Server) wechatLogin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Code string `json:"code"`
	}
	if err := decode(r, &body); err != nil || body.Code == "" || len(body.Code) > 128 {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	if s.DevAuth && strings.HasPrefix(body.Code, "dev:") {
		user := strings.TrimPrefix(body.Code, "dev:")
		if !devUserID.MatchString(user) {
			writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
			return
		}
		if err := s.ensureUser(r.Context(), user, user); err != nil {
			writeErr(w, http.StatusInternalServerError, "INTERNAL", "internal", nil)
			return
		}
		s.writeTokenSession(w, r, user, user, "dev")
		return
	}
	if !s.wechatReady() {
		writeErr(w, http.StatusServiceUnavailable, "WECHAT_NOT_CONFIGURED", "wechatNotConfigured", map[string]any{
			"need": []string{"WECHAT_APPID", "WECHAT_APPSECRET"},
		})
		return
	}
	openid, unionid, err := s.exchangeWechatCode(r.Context(), body.Code)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "WECHAT_CODE_INVALID", "wechatCodeInvalid", nil)
		return
	}
	userID, name, err := s.upsertWechatUser(r.Context(), openid, unionid)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "INTERNAL", "internal", nil)
		return
	}
	s.writeTokenSession(w, r, userID, name, "wechat")
}

func (s *Server) writeTokenSession(w http.ResponseWriter, r *http.Request, userID, name, mode string) {
	token, err := s.issueSession(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "INTERNAL", "internal", nil)
		return
	}
	s.writeSessionCookie(w, r, token)
	writeJSON(w, http.StatusOK, map[string]any{
		"userId":      userID,
		"displayName": name,
		"token":       token,
		"mode":        mode,
		"expiresIn":   7 * 24 * 3600,
	}, true)
}

func (s *Server) exchangeWechatCode(ctx context.Context, code string) (string, string, error) {
	endpoint := s.WechatEndpoint
	if endpoint == "" {
		endpoint = "https://api.weixin.qq.com/sns/jscode2session"
	}
	query := url.Values{}
	query.Set("appid", s.WechatAppID)
	query.Set("secret", s.WechatAppSecret)
	query.Set("js_code", code)
	query.Set("grant_type", "authorization_code")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint+"?"+query.Encode(), nil)
	if err != nil {
		return "", "", err
	}
	client := s.WechatHTTP
	if client == nil {
		client = &http.Client{
			Timeout: 8 * time.Second,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}
	}
	res, err := client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, 4096))
	if err != nil {
		return "", "", err
	}
	var parsed struct {
		OpenID  string `json:"openid"`
		UnionID string `json:"unionid"`
		ErrCode int    `json:"errcode"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", "", err
	}
	if parsed.ErrCode != 0 || parsed.OpenID == "" {
		return "", "", errors.New("wechat code rejected")
	}
	return parsed.OpenID, parsed.UnionID, nil
}

func (s *Server) upsertWechatUser(ctx context.Context, openid, unionid string) (string, string, error) {
	var userID, name string
	err := s.Store.Pool.QueryRow(ctx, `
		SELECT a.id, a.display_name
		FROM wechat_identities w
		JOIN accounts a ON a.id = w.user_id
		WHERE w.openid = $1
	`, openid).Scan(&userID, &name)
	if err == nil {
		return userID, name, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", "", err
	}
	sum := sha256.Sum256([]byte(openid))
	userID = "wx" + hex.EncodeToString(sum[:12])
	name = "微信用户"
	if err := s.ensureUser(ctx, userID, name); err != nil {
		return "", "", err
	}
	var union any
	if unionid != "" {
		union = unionid
	}
	tag, err := s.Store.Pool.Exec(ctx, `
		INSERT INTO wechat_identities (openid, user_id, unionid) VALUES ($1,$2,$3)
		ON CONFLICT (openid) DO NOTHING
	`, openid, userID, union)
	if err != nil {
		return "", "", err
	}
	if tag.RowsAffected() == 0 {
		if err := s.Store.Pool.QueryRow(ctx, `
			SELECT a.id, a.display_name
			FROM wechat_identities w
			JOIN accounts a ON a.id = w.user_id
			WHERE w.openid = $1
		`, openid).Scan(&userID, &name); err != nil {
			return "", "", err
		}
	}
	return userID, name, nil
}
