package api

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"mhbuddy/services/api/internal/ai"
)

type Server struct {
	Store      *Store
	DevAuth    bool
	ContentDir string
	WebRoot    string
	AI         *ai.Service
	mux        *http.ServeMux
}

func New(pool *pgxpool.Pool, dev bool, contentDir, webRoot string) *Server {
	s := &Server{Store: &Store{Pool: pool}, DevAuth: dev, ContentDir: contentDir, WebRoot: webRoot}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /v1/packs/latest", s.packs)
	mux.HandleFunc("GET /v1/events", s.events)
	mux.HandleFunc("GET /v1/events/{id}/calendar.ics", s.calendar)
	mux.HandleFunc("GET /v1/events/{id}", s.eventByID)
	mux.HandleFunc("GET /v1/articles", s.articles)
	mux.HandleFunc("GET /v1/public-builds", s.listPublic)
	mux.HandleFunc("POST /v1/public-builds", s.publish)
	mux.HandleFunc("GET /v1/public-builds/{id}", s.getPublic)
	mux.HandleFunc("DELETE /v1/public-builds/{id}", s.retract)
	mux.HandleFunc("POST /v1/auth/session", s.login)
	mux.HandleFunc("DELETE /v1/auth/session", s.logout)
	mux.HandleFunc("POST /v1/auth/refresh", s.refresh)
	mux.HandleFunc("POST /v1/reminders/subscriptions", s.subscribe)
	mux.HandleFunc("DELETE /v1/reminders/subscriptions/{id}", s.unsubscribe)
	mux.HandleFunc("GET /v1/me/entitlement", s.entitlement)
	mux.HandleFunc("POST /v1/sync/push", s.push)
	mux.HandleFunc("GET /v1/sync/pull", s.pull)
	mux.HandleFunc("GET /v1/sync/snapshot", s.snapshot)
	mux.HandleFunc("POST /v1/dev/events/{id}", s.devEvent)
	mux.HandleFunc("POST /v1/dev/entitlement", s.devEntitlement)
	mux.HandleFunc("POST /v1/dev/compact", s.devCompact)
	mux.HandleFunc("GET /v1/dev/reminder-jobs", s.devJobs)
	mux.HandleFunc("GET /v1/ai/status", s.aiStatus)
	mux.HandleFunc("POST /v1/ai/understand", s.aiUnderstand)
	s.mux = mux
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "same-origin")
	if strings.HasPrefix(r.URL.Path, "/v1/") || r.URL.Path == "/healthz" {
		if r.Method == http.MethodPost || r.Method == http.MethodPut || r.Method == http.MethodDelete {
			if !csrfOK(r) {
				writeErr(w, http.StatusForbidden, "CSRF", "csrf", nil)
				return
			}
		}
		s.mux.ServeHTTP(w, r)
		return
	}
	s.static(w, r)
}

func csrfOK(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return false
	}
	host := r.Host
	if xf := r.Header.Get("X-Forwarded-Host"); xf != "" {
		host = xf
	}
	o := strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
	o = strings.Split(o, "/")[0]
	return strings.EqualFold(o, host)
}

func writeErr(w http.ResponseWriter, status int, code, key string, details any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "private, no-store")
	id := randHex(8)
	w.Header().Set("X-Request-Id", id)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"code": code, "messageKey": key, "requestId": id, "details": details})
}

func writeJSON(w http.ResponseWriter, status int, v any, private bool) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if private {
		w.Header().Set("Cache-Control", "private, no-store")
	} else {
		w.Header().Set("Cache-Control", "public, max-age=60")
	}
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.Store.Pool.Ping(ctx); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "DB", "dbUnavailable", nil)
		return
	}
	writeJSON(w, 200, map[string]string{"status": "ok"}, false)
}

func (s *Server) currentUser(r *http.Request) (string, bool) {
	c, err := r.Cookie("mh_session")
	if err != nil || c.Value == "" {
		return "", false
	}
	sum := sha256.Sum256([]byte(c.Value))
	hash := hex.EncodeToString(sum[:])
	var user string
	err = s.Store.Pool.QueryRow(r.Context(), `
		SELECT user_id FROM sessions WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at > now()
	`, hash).Scan(&user)
	if err != nil {
		return "", false
	}
	return user, true
}

func (s *Server) setSession(w http.ResponseWriter, r *http.Request, user string) error {
	token := randHex(32)
	sum := sha256.Sum256([]byte(token))
	_, err := s.Store.Pool.Exec(r.Context(), `
		INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ($1,$2, now() + interval '7 days')
	`, hex.EncodeToString(sum[:]), user)
	if err != nil {
		return err
	}
	secure := r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
	http.SetCookie(w, &http.Cookie{
		Name: "mh_session", Value: token, Path: "/", HttpOnly: true,
		SameSite: http.SameSiteLaxMode, Secure: secure, MaxAge: 7 * 24 * 3600,
	})
	return nil
}

func quotaFor(user string) (string, int64) {
	if user == "hunter-b" {
		return "member-small", 800
	}
	return "member", 20000
}

func (s *Server) ensureUser(ctx context.Context, id, name string) error {
	if name == "" {
		name = id
	}
	plan, quota := quotaFor(id)
	tx, err := s.Store.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `INSERT INTO accounts (id, display_name) VALUES ($1,$2) ON CONFLICT (id) DO NOTHING`, id, name); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `
		INSERT INTO entitlements (user_id, plan_id, quota_bytes, used_bytes) VALUES ($1,$2,$3,0)
		ON CONFLICT (user_id) DO NOTHING
	`, id, plan, quota); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO account_state (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if !s.DevAuth {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "notFound", nil)
		return
	}
	var body struct {
		Provider    string `json:"provider"`
		UserID      string `json:"userId"`
		DisplayName string `json:"displayName"`
	}
	if err := decode(r, &body); err != nil || body.Provider != "dev" || body.UserID == "" || len(body.UserID) > 64 {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	if err := s.ensureUser(r.Context(), body.UserID, body.DisplayName); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	if err := s.setSession(w, r, body.UserID); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]string{"userId": body.UserID}, true)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie("mh_session"); err == nil {
		sum := sha256.Sum256([]byte(c.Value))
		_, _ = s.Store.Pool.Exec(r.Context(), `UPDATE sessions SET revoked_at=now() WHERE token_hash=$1`, hex.EncodeToString(sum[:]))
	}
	http.SetCookie(w, &http.Cookie{Name: "mh_session", Value: "", Path: "/", MaxAge: -1, HttpOnly: true})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	if c, err := r.Cookie("mh_session"); err == nil {
		sum := sha256.Sum256([]byte(c.Value))
		_, _ = s.Store.Pool.Exec(r.Context(), `UPDATE sessions SET revoked_at=now() WHERE token_hash=$1`, hex.EncodeToString(sum[:]))
	}
	if err := s.setSession(w, r, user); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]string{"userId": user}, true)
}

func decode(r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20)
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func decodeLoose(r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20)
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

func (s *Server) push(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	var body struct {
		Ops []Op `json:"ops"`
	}
	if err := decodeLoose(r, &body); err != nil || len(body.Ops) == 0 || len(body.Ops) > 50 {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	results := make([]Result, 0, len(body.Ops))
	for _, op := range body.Ops {
		res, err := s.Store.Apply(r.Context(), user, op)
		if err != nil {
			writeErr(w, 500, "INTERNAL", "internal", nil)
			return
		}
		results = append(results, res)
	}
	writeJSON(w, 200, map[string]any{"results": results}, true)
}

func (s *Server) pull(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	since, _ := strconv.ParseInt(r.URL.Query().Get("cursor"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	changes, next, err := s.Store.Pull(r.Context(), user, since, limit)
	if err != nil && errors.Is(err, errCursorExpired) {
		writeErr(w, http.StatusConflict, "CURSOR_EXPIRED", "cursorExpired", nil)
		return
	}
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"changes": changes, "nextCursor": next}, true)
}

func (s *Server) snapshot(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	snap, err := s.Store.Snapshot(r.Context(), user)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, snap, true)
}

func (s *Server) entitlement(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	var plan string
	var quota, used int64
	var exp *time.Time
	err := s.Store.Pool.QueryRow(r.Context(), `SELECT plan_id, quota_bytes, used_bytes, expires_at FROM entitlements WHERE user_id=$1`, user).Scan(&plan, &quota, &used, &exp)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"userId": user, "planId": plan, "quotaBytes": quota, "usedBytes": used, "expiresAt": exp}, true)
}

func (s *Server) devEntitlement(w http.ResponseWriter, r *http.Request) {
	if !s.DevAuth {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "notFound", nil)
		return
	}
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	var body struct {
		PlanID     string `json:"planId"`
		QuotaBytes int64  `json:"quotaBytes"`
	}
	if err := decode(r, &body); err != nil || body.QuotaBytes < 0 {
		writeErr(w, 422, "VALIDATION", "validation", nil)
		return
	}
	if err := s.Store.SetEntitlement(r.Context(), user, body.PlanID, body.QuotaBytes); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"planId": body.PlanID, "quotaBytes": body.QuotaBytes}, true)
}

func (s *Server) devCompact(w http.ResponseWriter, r *http.Request) {
	if !s.DevAuth {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "notFound", nil)
		return
	}
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	if err := s.Store.Compact(r.Context(), user); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) packs(w http.ResponseWriter, r *http.Request) {
	game := r.URL.Query().Get("gameId")
	if game != "world" && game != "wilds" {
		writeErr(w, 422, "NO_COMPATIBLE_PACK", "noCompatiblePack", nil)
		return
	}
	path := filepath.Join(s.ContentDir, "manifests", game+".json")
	body, err := os.ReadFile(path)
	if err != nil {
		writeErr(w, 422, "NO_COMPATIBLE_PACK", "noCompatiblePack", nil)
		return
	}
	var man Manifest
	if err := json.Unmarshal(body, &man); err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	if cv := r.URL.Query().Get("clientVersion"); cv != "" && versionLess(cv, man.MinClient) {
		writeErr(w, 422, "INCOMPATIBLE_CLIENT", "incompatibleClient", map[string]string{"minClient": man.MinClient})
		return
	}
	sum := sha256.Sum256(body)
	etag := `"` + hex.EncodeToString(sum[:]) + `"`
	w.Header().Set("ETag", etag)
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=60")
	w.WriteHeader(200)
	_, _ = w.Write(body)
}

func versionLess(a, b string) bool {
	ap := strings.Split(a, ".")
	bp := strings.Split(b, ".")
	for i := 0; i < len(ap) || i < len(bp); i++ {
		var av, bv int
		if i < len(ap) {
			av, _ = strconv.Atoi(ap[i])
		}
		if i < len(bp) {
			bv, _ = strconv.Atoi(bp[i])
		}
		if av < bv {
			return true
		}
		if av > bv {
			return false
		}
	}
	return false
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	game := r.URL.Query().Get("gameId")
	q := strings.ToLower(r.URL.Query().Get("q"))
	reward := strings.ToLower(r.URL.Query().Get("reward"))
	rows, err := s.Store.Pool.Query(r.Context(), `SELECT id, game_id, platform_id, region, titles, rewards, starts_at, ends_at, timezone, status, verified_at, source_url, conditions, sequence FROM events ORDER BY id`)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	defer rows.Close()
	list := filterEvents(rows, game, q, reward)
	writeJSON(w, 200, map[string]any{"events": list}, false)
}

func (s *Server) eventByID(w http.ResponseWriter, r *http.Request) {
	ev, ok := s.loadEvent(r, r.PathValue("id"))
	if !ok {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	writeJSON(w, 200, ev, false)
}

func (s *Server) loadEvent(r *http.Request, id string) (map[string]any, bool) {
	var game, platform, region, tz, status, source, cond string
	var titles, rewards []byte
	var start, end, verified *time.Time
	var seq int
	err := s.Store.Pool.QueryRow(r.Context(), `SELECT game_id, platform_id, region, titles, rewards, starts_at, ends_at, timezone, status, verified_at, source_url, conditions, sequence FROM events WHERE id=$1`, id).
		Scan(&game, &platform, &region, &titles, &rewards, &start, &end, &tz, &status, &verified, &source, &cond, &seq)
	if err != nil {
		return nil, false
	}
	return map[string]any{
		"id": id, "gameId": game, "platformId": platform, "region": region,
		"titles": json.RawMessage(titles), "rewards": json.RawMessage(rewards),
		"startsAt": start, "endsAt": end, "timezone": tz, "status": status,
		"verifiedAt": verified, "sourceUrl": source, "conditions": cond, "sequence": seq, "fixture": true,
	}, true
}

func filterEvents(rows pgx.Rows, game, q, reward string) []map[string]any {
	var list []map[string]any
	for rows.Next() {
		var id, gameID, platform, region, tz, status, source, cond string
		var titles, rewards []byte
		var start, end, verified *time.Time
		var seq int
		if err := rows.Scan(&id, &gameID, &platform, &region, &titles, &rewards, &start, &end, &tz, &status, &verified, &source, &cond, &seq); err != nil {
			continue
		}
		if game != "" && gameID != game {
			continue
		}
		blob := strings.ToLower(string(titles))
		rew := strings.ToLower(string(rewards))
		if q != "" && !strings.Contains(blob, q) {
			continue
		}
		if reward != "" && !strings.Contains(rew, reward) {
			continue
		}
		list = append(list, map[string]any{
			"id": id, "gameId": gameID, "platformId": platform, "region": region,
			"titles": json.RawMessage(titles), "rewards": json.RawMessage(rewards),
			"startsAt": start, "endsAt": end, "timezone": tz, "status": status,
			"verifiedAt": verified, "sourceUrl": source, "conditions": cond, "sequence": seq, "fixture": true,
		})
	}
	if list == nil {
		list = []map[string]any{}
	}
	return list
}

func (s *Server) calendar(w http.ResponseWriter, r *http.Request) {
	ev, ok := s.loadEvent(r, r.PathValue("id"))
	if !ok {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	titles := map[string]string{}
	_ = json.Unmarshal(ev["titles"].(json.RawMessage), &titles)
	summary := titles["zh-Hans"]
	start, _ := ev["startsAt"].(*time.Time)
	end, _ := ev["endsAt"].(*time.Time)
	seq, _ := ev["sequence"].(int)
	fmtICS := func(t *time.Time) string {
		if t == nil {
			return ""
		}
		return t.UTC().Format("20060102T150405Z")
	}
	body := "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//MHBuddy//Fixture//ZH\r\nBEGIN:VEVENT\r\nUID:" + ev["id"].(string) + "@mhbuddy.local\r\nSEQUENCE:" + strconv.Itoa(seq) + "\r\nDTSTAMP:" + time.Now().UTC().Format("20060102T150405Z") + "\r\n"
	if start != nil {
		body += "DTSTART:" + fmtICS(start) + "\r\n"
	}
	if end != nil {
		body += "DTEND:" + fmtICS(end) + "\r\n"
	}
	body += "SUMMARY:" + summary + "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.WriteHeader(200)
	_, _ = io.WriteString(w, body)
}

func (s *Server) devEvent(w http.ResponseWriter, r *http.Request) {
	if !s.DevAuth {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	var body struct {
		StartsAt *time.Time `json:"startsAt"`
		EndsAt   *time.Time `json:"endsAt"`
		Status   string     `json:"status"`
	}
	if err := decodeLoose(r, &body); err != nil {
		writeErr(w, 422, "VALIDATION", "validation", nil)
		return
	}
	id := r.PathValue("id")
	tag, err := s.Store.Pool.Exec(r.Context(), `
		UPDATE events SET starts_at=COALESCE($2, starts_at), ends_at=COALESCE($3, ends_at),
		  status=CASE WHEN $4 <> '' THEN $4 ELSE status END, sequence=sequence+1, verified_at=now()
		WHERE id=$1
	`, id, body.StartsAt, body.EndsAt, body.Status)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	if body.Status == "revoked" {
		_, _ = s.Store.Pool.Exec(r.Context(), `UPDATE reminder_jobs SET status='cleared' WHERE event_id=$1 AND status='pending'`, id)
	} else if body.StartsAt != nil {
		_, _ = s.Store.Pool.Exec(r.Context(), `UPDATE reminder_jobs SET fire_at=$2, status='pending' WHERE event_id=$1 AND status='pending'`, id, body.StartsAt.Add(-30*time.Minute))
	}
	ev, _ := s.loadEvent(r, id)
	writeJSON(w, 200, ev, true)
}

func (s *Server) devJobs(w http.ResponseWriter, r *http.Request) {
	if !s.DevAuth {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	id := r.URL.Query().Get("eventId")
	rows, err := s.Store.Pool.Query(r.Context(), `SELECT id, status, fire_at FROM reminder_jobs WHERE event_id=$1 ORDER BY id`, id)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	defer rows.Close()
	var list []map[string]any
	for rows.Next() {
		var jid, status string
		var fire *time.Time
		if err := rows.Scan(&jid, &status, &fire); err != nil {
			continue
		}
		list = append(list, map[string]any{"id": jid, "status": status, "fireAt": fire})
	}
	if list == nil {
		list = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"jobs": list}, true)
}

func (s *Server) articles(w http.ResponseWriter, r *http.Request) {
	game := r.URL.Query().Get("gameId")
	rows, err := s.Store.Pool.Query(r.Context(), `SELECT id, game_id, locale, title, body, source_url, original_language, review_status, verified_at FROM articles WHERE ($1='' OR game_id=$1) ORDER BY id`, game)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	defer rows.Close()
	var list []map[string]any
	for rows.Next() {
		var id, gameID, locale, title, body, source, lang, review string
		var verified time.Time
		if err := rows.Scan(&id, &gameID, &locale, &title, &body, &source, &lang, &review, &verified); err != nil {
			continue
		}
		list = append(list, map[string]any{"id": id, "gameId": gameID, "locale": locale, "title": title, "body": body, "sourceUrl": source, "originalLanguage": lang, "reviewStatus": review, "verifiedAt": verified})
	}
	if list == nil {
		list = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"articles": list}, false)
}

func (s *Server) listPublic(w http.ResponseWriter, r *http.Request) {
	game := r.URL.Query().Get("gameId")
	weapon := r.URL.Query().Get("weaponType")
	rarity, _ := strconv.Atoi(r.URL.Query().Get("rarity"))
	rows, err := s.Store.Pool.Query(r.Context(), `
		SELECT id, game_id, title, weapon_type, rarity, snapshot, created_at FROM public_builds
		WHERE retracted_at IS NULL AND ($1='' OR game_id=$1) AND ($2='' OR weapon_type=$2) AND ($3=0 OR rarity=$3)
		ORDER BY id
	`, game, weapon, rarity)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	defer rows.Close()
	var list []map[string]any
	for rows.Next() {
		var id, gameID, title, weaponType string
		var rar int
		var snap []byte
		var created time.Time
		if err := rows.Scan(&id, &gameID, &title, &weaponType, &rar, &snap, &created); err != nil {
			continue
		}
		list = append(list, map[string]any{"id": id, "gameId": gameID, "title": title, "weaponType": weaponType, "rarity": rar, "snapshot": json.RawMessage(snap), "createdAt": created})
	}
	if list == nil {
		list = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"builds": list}, false)
}

func (s *Server) publish(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, 401, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	var body struct {
		Title      string          `json:"title"`
		GameID     string          `json:"gameId"`
		WeaponType string          `json:"weaponType"`
		Rarity     int             `json:"rarity"`
		Snapshot   json.RawMessage `json:"snapshot"`
	}
	if err := decodeLoose(r, &body); err != nil || body.Title == "" || (body.GameID != "world" && body.GameID != "wilds") || !json.Valid(body.Snapshot) {
		writeErr(w, 422, "VALIDATION", "validation", nil)
		return
	}
	id := "pub-" + randHex(8)
	_, err := s.Store.Pool.Exec(r.Context(), `
		INSERT INTO public_builds (id, owner_id, game_id, title, weapon_type, rarity, snapshot) VALUES ($1,$2,$3,$4,$5,$6,$7)
	`, id, user, body.GameID, body.Title, body.WeaponType, body.Rarity, body.Snapshot)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 201, map[string]any{"id": id, "status": "published"}, true)
}

func (s *Server) getPublic(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var game, title, weapon, owner string
	var rar int
	var snap []byte
	var retracted *time.Time
	err := s.Store.Pool.QueryRow(r.Context(), `SELECT owner_id, game_id, title, weapon_type, rarity, snapshot, retracted_at FROM public_builds WHERE id=$1`, id).
		Scan(&owner, &game, &title, &weapon, &rar, &snap, &retracted)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	if retracted != nil {
		writeErr(w, http.StatusGone, "RETRACTED", "retracted", map[string]any{"id": id})
		return
	}
	_ = owner
	writeJSON(w, 200, map[string]any{"id": id, "gameId": game, "title": title, "weaponType": weapon, "rarity": rar, "snapshot": json.RawMessage(snap), "status": "published"}, false)
}

func (s *Server) retract(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, 401, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	id := r.PathValue("id")
	var owner string
	var retracted *time.Time
	err := s.Store.Pool.QueryRow(r.Context(), `SELECT owner_id, retracted_at FROM public_builds WHERE id=$1`, id).Scan(&owner, &retracted)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	if owner != user {
		writeErr(w, 403, "FORBIDDEN", "forbidden", nil)
		return
	}
	_, err = s.Store.Pool.Exec(r.Context(), `UPDATE public_builds SET retracted_at=now() WHERE id=$1`, id)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) subscribe(w http.ResponseWriter, r *http.Request) {
	var body struct {
		EventID     string `json:"eventId"`
		PlatformID  string `json:"platformId"`
		Kind        string `json:"kind"`
		Endpoint    string `json:"endpoint"`
		RevokeToken string `json:"revokeToken"`
	}
	if err := decodeLoose(r, &body); err != nil || body.EventID == "" || body.Kind == "" {
		writeErr(w, 422, "VALIDATION", "validation", nil)
		return
	}
	user, logged := s.currentUser(r)
	subject := ""
	revokeHash := ""
	if logged {
		subject = "user:" + user
	} else {
		if body.RevokeToken == "" {
			writeErr(w, 422, "VALIDATION", "validation", nil)
			return
		}
		sum := sha256.Sum256([]byte(body.RevokeToken))
		revokeHash = hex.EncodeToString(sum[:])
		subject = "browser:" + revokeHash[:16]
	}
	var exists int
	if err := s.Store.Pool.QueryRow(r.Context(), `SELECT COUNT(*) FROM events WHERE id=$1`, body.EventID).Scan(&exists); err != nil || exists == 0 {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	id := "rem-" + randHex(8)
	if body.PlatformID == "" {
		body.PlatformID = "pc"
	}
	err := s.Store.Pool.QueryRow(r.Context(), `
		INSERT INTO reminder_subs (id, subject, event_id, platform_id, remind_kind, endpoint, revoke_hash)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT (subject, event_id, platform_id, remind_kind) DO UPDATE SET endpoint=EXCLUDED.endpoint
		RETURNING id
	`, id, subject, body.EventID, body.PlatformID, body.Kind, body.Endpoint, revokeHash).Scan(&id)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	var start *time.Time
	_ = s.Store.Pool.QueryRow(r.Context(), `SELECT starts_at FROM events WHERE id=$1`, body.EventID).Scan(&start)
	var fire *time.Time
	if start != nil {
		t := start.Add(-30 * time.Minute)
		fire = &t
	}
	_, _ = s.Store.Pool.Exec(r.Context(), `DELETE FROM reminder_jobs WHERE sub_id=$1 AND status='pending'`, id)
	_, _ = s.Store.Pool.Exec(r.Context(), `INSERT INTO reminder_jobs (id, sub_id, event_id, fire_at, status) VALUES ($1,$2,$3,$4,'pending')`, "job-"+randHex(6), id, body.EventID, fire)
	writeJSON(w, 201, map[string]string{"id": id}, true)
}

func (s *Server) unsubscribe(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var subject, revokeHash string
	err := s.Store.Pool.QueryRow(r.Context(), `SELECT subject, revoke_hash FROM reminder_subs WHERE id=$1`, id).Scan(&subject, &revokeHash)
	if err != nil {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	user, logged := s.currentUser(r)
	var body struct {
		RevokeToken string `json:"revokeToken"`
	}
	_ = decodeLoose(r, &body)
	ok := false
	if logged && subject == "user:"+user {
		ok = true
	}
	if body.RevokeToken != "" {
		sum := sha256.Sum256([]byte(body.RevokeToken))
		if hex.EncodeToString(sum[:]) == revokeHash {
			ok = true
		}
	}
	if !ok {
		writeErr(w, 403, "FORBIDDEN", "forbidden", nil)
		return
	}
	_, _ = s.Store.Pool.Exec(r.Context(), `DELETE FROM reminder_subs WHERE id=$1`, id)
	w.WriteHeader(http.StatusNoContent)
}

var appRoute = regexp.MustCompile(`^/$|^/me$|^/offline$|^/builds/[A-Za-z0-9._-]+$|^/g/(world|wilds)(/entries(/[a-z0-9-]+/[A-Za-z0-9._-]+)?)?$|^/g/(world|wilds)/maps(/[A-Za-z0-9._-]+)?$|^/g/(world|wilds)/builds$|^/g/(world|wilds)/events(/[A-Za-z0-9._-]+)?$`)

func (s *Server) static(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeErr(w, 404, "NOT_FOUND", "notFound", nil)
		return
	}
	clean := path.Clean("/" + r.URL.Path)
	if strings.HasPrefix(clean, "/fixtures/") || clean == "/fixtures" {
		rel := strings.TrimPrefix(clean, "/fixtures")
		rel = strings.TrimPrefix(rel, "/")
		full := filepath.Join(s.ContentDir, filepath.FromSlash(rel))
		if !strings.HasPrefix(full, filepath.Clean(s.ContentDir)+string(os.PathSeparator)) && full != filepath.Clean(s.ContentDir) {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, full)
		return
	}
	if s.WebRoot == "" {
		http.NotFound(w, r)
		return
	}
	root, _ := filepath.Abs(s.WebRoot)
	full := filepath.Join(root, filepath.FromSlash(clean))
	if !strings.HasPrefix(full, root) {
		http.NotFound(w, r)
		return
	}
	if info, err := os.Stat(full); err == nil && !info.IsDir() {
		http.ServeFile(w, r, full)
		return
	}
	if appRoute.MatchString(clean) {
		http.ServeFile(w, r, filepath.Join(root, "index.html"))
		return
	}
	http.NotFound(w, r)
}

func Migrate(ctx context.Context, pool *pgxpool.Pool, sqlText string) error {
	_, err := pool.Exec(ctx, sqlText)
	return err
}

func EnsureDatabase(ctx context.Context, adminDSN, name string) error {
	conn, err := pgx.Connect(ctx, adminDSN)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	var exists bool
	if err := conn.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname=$1)`, name).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		if _, err := conn.Exec(ctx, `CREATE DATABASE `+pgIdent(name)); err != nil {
			return err
		}
	}
	return nil
}

func pgIdent(name string) string {
	if name != "mhbuddy" && name != "mhbuddy_test" && name != "postgres" {
		return "mhbuddy"
	}
	return name
}

func Locate(rel string) (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for i := 0; i < 8; i++ {
		p := filepath.Join(dir, rel)
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
		dir = filepath.Dir(dir)
	}
	return "", os.ErrNotExist
}

func Seed(ctx context.Context, pool *pgxpool.Pool, contentDir string) error {
	if err := seedEvents(ctx, pool, filepath.Join(contentDir, "events.json")); err != nil {
		return err
	}
	if err := seedArticles(ctx, pool, filepath.Join(contentDir, "articles.json")); err != nil {
		return err
	}
	return seedPublic(ctx, pool, filepath.Join(contentDir, "public-builds.json"))
}

func seedEvents(ctx context.Context, pool *pgxpool.Pool, path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var rows []map[string]any
	if err := json.Unmarshal(raw, &rows); err != nil {
		return err
	}
	for _, row := range rows {
		titles, _ := json.Marshal(row["titles"])
		rewards, _ := json.Marshal(row["rewards"])
		_, err := pool.Exec(ctx, `
			INSERT INTO events (id, game_id, platform_id, region, titles, rewards, starts_at, ends_at, timezone, status, verified_at, source_url, conditions, sequence)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
			ON CONFLICT (id) DO NOTHING
		`, row["id"], row["gameId"], row["platformId"], row["region"], titles, rewards, parseTime(row["startsAt"]), parseTime(row["endsAt"]), row["timezone"], row["status"], parseTime(row["verifiedAt"]), str(row["sourceUrl"]), str(row["conditions"]), intOf(row["sequence"]))
		if err != nil {
			return err
		}
	}
	return nil
}

func seedArticles(ctx context.Context, pool *pgxpool.Pool, path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var rows []map[string]any
	if err := json.Unmarshal(raw, &rows); err != nil {
		return err
	}
	for _, row := range rows {
		_, err := pool.Exec(ctx, `
			INSERT INTO articles (id, game_id, locale, title, body, source_url, original_language, review_status, verified_at)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT (id) DO NOTHING
		`, row["id"], row["gameId"], row["locale"], row["title"], row["body"], str(row["sourceUrl"]), row["originalLanguage"], row["reviewStatus"], parseTime(row["verifiedAt"]))
		if err != nil {
			return err
		}
	}
	return nil
}

func seedPublic(ctx context.Context, pool *pgxpool.Pool, path string) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var rows []map[string]any
	if err := json.Unmarshal(raw, &rows); err != nil {
		return err
	}
	for _, row := range rows {
		snap, _ := json.Marshal(row["snapshot"])
		_, err := pool.Exec(ctx, `
			INSERT INTO public_builds (id, owner_id, game_id, title, weapon_type, rarity, snapshot)
			VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING
		`, row["id"], row["ownerId"], row["gameId"], row["title"], str(row["weaponType"]), intOf(row["rarity"]), snap)
		if err != nil {
			return err
		}
	}
	return nil
}

func parseTime(v any) any {
	s, ok := v.(string)
	if !ok || s == "" {
		return nil
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return nil
	}
	return t
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

func intOf(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return 0
	}
}

// PublicKeyFromHex decodes the fixture verify key.
func PublicKeyFromHex(h string) (ed25519.PublicKey, error) {
	b, err := hex.DecodeString(strings.TrimSpace(h))
	if err != nil {
		return nil, err
	}
	return ed25519.PublicKey(b), nil
}
