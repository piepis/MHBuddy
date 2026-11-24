package api

import (
	"context"
	"encoding/json"
	"html"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const anonCookie = "mh_anon"

var (
	idPattern    = regexp.MustCompile(`^[A-Za-z0-9_.:-]{1,64}$`)
	stylePattern = regexp.MustCompile(`^[\p{L}\p{N}_-]{1,16}$`)
	pathPattern  = regexp.MustCompile(`^/[\p{L}\p{N}_./:?=&%-]{0,160}$`)
	purgeOnce    sync.Once
)

func adminIDs(env string, args []string) map[string]struct{} {
	out := map[string]struct{}{}
	add := func(raw string) {
		for _, part := range strings.Split(raw, ",") {
			id := strings.TrimSpace(part)
			if id != "" && len(id) <= 64 {
				out[id] = struct{}{}
			}
		}
	}
	add(env)
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--admin" && i+1 < len(args) {
			add(args[i+1])
			i++
			continue
		}
		if strings.HasPrefix(arg, "--admin=") {
			add(strings.TrimPrefix(arg, "--admin="))
		}
	}
	return out
}

func currentAdmins() map[string]struct{} {
	return adminIDs(os.Getenv("MH_ADMINS"), os.Args)
}

func analyticsK() int {
	n := 5
	if raw := os.Getenv("MH_ANALYTICS_K"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v >= 1 && v <= 1000 {
			n = v
		}
	}
	return n
}

func retentionDays() int {
	n := 180
	if raw := os.Getenv("MH_ANALYTICS_RETENTION_DAYS"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v >= 1 && v <= 3650 {
			n = v
		}
	}
	return n
}

func (s *Server) serveAnalytics(w http.ResponseWriter, r *http.Request) bool {
	path := r.URL.Path
	switch {
	case path == "/assets/analytics/NotoSansSC-400.ttf" && r.Method == http.MethodGet:
		s.serveFont(w, r)
		return true
	case path == "/privacy" && (r.Method == http.MethodGet || r.Method == http.MethodHead):
		s.privacyPage(w, r)
		return true
	case path == "/admin" && (r.Method == http.MethodGet || r.Method == http.MethodHead):
		s.adminPage(w, r)
		return true
	case path == "/v1/admin/metrics" && r.Method == http.MethodGet:
		s.adminMetrics(w, r)
		return true
	case path == "/v1/analytics/collect" && r.Method == http.MethodPost:
		s.collect(w, r)
		return true
	case path == "/v1/me/preferences" && (r.Method == http.MethodGet || r.Method == http.MethodPut):
		s.preferences(w, r)
		return true
	case path == "/v1/ai/usage" && r.Method == http.MethodPost:
		s.recordAIUsage(w, r)
		return true
	default:
		return false
	}
}

func (s *Server) serveFont(w http.ResponseWriter, r *http.Request) {
	p, err := Locate("apps/web/fonts/NotoSansSC-400.ttf")
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFile(w, r, p)
}

func (s *Server) isAdmin(r *http.Request) bool {
	user, ok := s.currentUser(r)
	if !ok {
		return false
	}
	_, yes := currentAdmins()[user]
	return yes
}

func (s *Server) denyAdmin(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet && r.URL.Path == "/admin" {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "private, no-store")
		w.Header().Set("X-Robots-Tag", "noindex")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(notFoundHTML))
		return
	}
	writeErr(w, http.StatusNotFound, "NOT_FOUND", "notFound", nil)
}

func (s *Server) purgeOld(ctx context.Context) {
	purgeOnce.Do(func() {
		days := retentionDays()
		_, _ = s.Store.Pool.Exec(ctx, `DELETE FROM analytics_events WHERE occurred_at < now() - ($1 || ' days')::interval`, strconv.Itoa(days))
		_, _ = s.Store.Pool.Exec(ctx, `DELETE FROM ai_usage_log WHERE occurred_at < now() - ($1 || ' days')::interval`, strconv.Itoa(days))
	})
}

func (s *Server) touchVisitor(ctx context.Context, r *http.Request, w http.ResponseWriter, when time.Time) (string, string) {
	id := ""
	if c, err := r.Cookie(anonCookie); err == nil && idPattern.MatchString(c.Value) && len(c.Value) == 32 {
		id = c.Value
	}
	if id == "" {
		id = randHex(16)
		secure := r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
		http.SetCookie(w, &http.Cookie{
			Name: anonCookie, Value: id, Path: "/", HttpOnly: true,
			SameSite: http.SameSiteLaxMode, Secure: secure, MaxAge: 400 * 24 * 3600,
		})
	}
	user, logged := s.currentUser(r)
	var userPtr *string
	if logged {
		userPtr = &user
	}
	if when.IsZero() {
		when = time.Now().UTC()
	}
	if _, err := s.Store.Pool.Exec(ctx, `
		INSERT INTO visitors (id, first_seen_at, last_seen_at)
		VALUES ($1, $2, $2)
		ON CONFLICT (id) DO UPDATE SET
		  first_seen_at = LEAST(visitors.first_seen_at, EXCLUDED.first_seen_at),
		  last_seen_at = GREATEST(visitors.last_seen_at, EXCLUDED.last_seen_at)
	`, id, when); err != nil {
		return "", err.Error()
	}
	if logged && userPtr != nil {
		_, _ = s.Store.Pool.Exec(ctx, `
			UPDATE visitors SET user_id = COALESCE(user_id, $2), linked_at = COALESCE(linked_at, $3) WHERE id = $1
		`, id, *userPtr, when)
	}
	if logged {
		return id, user
	}
	return id, ""
}

type collectBody struct {
	Type           string   `json:"type"`
	Path           string   `json:"path"`
	GameID         string   `json:"gameId"`
	ContentProfile string   `json:"contentProfile"`
	Query          string   `json:"query"`
	Kind           string   `json:"kind"`
	EntryID        string   `json:"entryId"`
	WeaponID       string   `json:"weaponId"`
	MonsterID      string   `json:"monsterId"`
	Styles         []string `json:"styles"`
	PublicID       string   `json:"publicId"`
	At             string   `json:"at"`
}

func (s *Server) collect(w http.ResponseWriter, r *http.Request) {
	if !csrfOK(r) {
		writeErr(w, http.StatusForbidden, "CSRF", "csrf", nil)
		return
	}
	s.purgeOld(r.Context())
	var body collectBody
	if err := decodeLoose(r, &body); err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	eventType := body.Type
	switch eventType {
	case "page_view", "search", "catalog_view", "build_generate", "build_share", "session":
	default:
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	when := time.Now().UTC()
	if body.At != "" && s.DevAuth {
		if t, err := time.Parse(time.RFC3339, body.At); err == nil {
			when = t.UTC()
		}
	}
	visitor, user := s.touchVisitor(r.Context(), r, w, when)
	if visitor == "" {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	query := normalizeQuery(body.Query)
	if eventType == "search" && query == "" {
		writeJSON(w, http.StatusNoContent, map[string]any{"ok": true, "stored": false}, true)
		return
	}
	styles, _ := json.Marshal(cleanStyles(body.Styles))
	var userArg any
	if user != "" {
		userArg = user
	}
	_, err := s.Store.Pool.Exec(r.Context(), `
		INSERT INTO analytics_events (
		  occurred_at, visitor_id, user_id, event_type, game_id, content_profile, path,
		  query_norm, kind, entry_id, weapon_id, monster_id, styles, public_id
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
	`, when, visitor, userArg, eventType, cleanGame(body.GameID), cleanProfile(body.ContentProfile), cleanPath(body.Path),
		query, cleanKind(body.Kind), cleanID(body.EntryID), cleanID(body.WeaponID), cleanID(body.MonsterID), styles, cleanID(body.PublicID))
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "stored": true}, true)
}

func normalizeQuery(q string) string {
	q = strings.TrimSpace(strings.ToLower(q))
	q = strings.Join(strings.Fields(q), " ")
	if utf8.RuneCountInString(q) > 80 {
		runes := []rune(q)
		q = string(runes[:80])
	}
	return q
}

func cleanID(v string) string {
	v = strings.TrimSpace(v)
	if idPattern.MatchString(v) {
		return v
	}
	return ""
}

func cleanGame(v string) string {
	if v == "world" || v == "wilds" {
		return v
	}
	return ""
}

func cleanProfile(v string) string {
	if v == "base" || v == "iceborne" {
		return v
	}
	return ""
}

func cleanKind(v string) string {
	switch v {
	case "weapon", "armor", "monster", "item", "skill", "material", "decoration", "talisman":
		return v
	default:
		return ""
	}
}

func cleanPath(v string) string {
	v = strings.TrimSpace(v)
	if pathPattern.MatchString(v) {
		return v
	}
	return ""
}

func cleanStyles(in []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, raw := range in {
		token := strings.TrimSpace(raw)
		if !stylePattern.MatchString(token) || seen[token] {
			continue
		}
		seen[token] = true
		out = append(out, token)
		if len(out) == 8 {
			break
		}
	}
	if out == nil {
		out = []string{}
	}
	return out
}

func cleanIDList(in []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, raw := range in {
		id := cleanID(raw)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
		if len(out) == 32 {
			break
		}
	}
	if out == nil {
		out = []string{}
	}
	return out
}

type aiUsageBody struct {
	GameID          string   `json:"gameId"`
	ContentProfile  string   `json:"contentProfile"`
	WeaponIDs       []string `json:"weaponIds"`
	MonsterIDs      []string `json:"monsterIds"`
	Styles          []string `json:"styles"`
	EntryIDs        []string `json:"entryIds"`
	InventoryIDs    []string `json:"inventoryIds"`
	ExcludedIDs     []string `json:"excludedIds"`
	AssumeUnlimited bool     `json:"assumeUnlimitedJewels"`
	Counted         bool     `json:"counted"`
}

func (s *Server) recordAIUsage(w http.ResponseWriter, r *http.Request) {
	if !csrfOK(r) {
		writeErr(w, http.StatusForbidden, "CSRF", "csrf", nil)
		return
	}
	s.purgeOld(r.Context())
	var body aiUsageBody
	if err := decodeLoose(r, &body); err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	weapons := cleanIDList(body.WeaponIDs)
	monsters := cleanIDList(body.MonsterIDs)
	styles := cleanStyles(body.Styles)
	entries := cleanIDList(body.EntryIDs)
	inventory := cleanIDList(body.InventoryIDs)
	excluded := cleanIDList(body.ExcludedIDs)
	game := cleanGame(body.GameID)
	if game == "" && len(weapons)+len(monsters)+len(styles)+len(entries)+len(inventory)+len(excluded) == 0 {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	visitor, user := s.touchVisitor(r.Context(), r, w, time.Now().UTC())
	subject := "anon:" + visitor
	var userArg any
	if user != "" {
		subject = "user:" + user
		userArg = user
	}
	wb, _ := json.Marshal(weapons)
	mb, _ := json.Marshal(monsters)
	sb, _ := json.Marshal(styles)
	eb, _ := json.Marshal(entries)
	ib, _ := json.Marshal(inventory)
	xb, _ := json.Marshal(excluded)
	_, err := s.Store.Pool.Exec(r.Context(), `
		INSERT INTO ai_usage_log (
		  subject, user_id, game_id, content_profile, weapon_ids, monster_ids, styles,
		  entry_ids, inventory_ids, excluded_ids, assume_unlimited, counted
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
	`, subject, userArg, game, cleanProfile(body.ContentProfile), wb, mb, sb, eb, ib, xb, body.AssumeUnlimited, body.Counted)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true}, true)
}

func (s *Server) preferences(w http.ResponseWriter, r *http.Request) {
	user, ok := s.currentUser(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized", nil)
		return
	}
	if r.Method == http.MethodGet {
		var locale, theme, profile string
		err := s.Store.Pool.QueryRow(r.Context(), `
			SELECT locale, theme, content_profile FROM account_preferences WHERE user_id=$1
		`, user).Scan(&locale, &theme, &profile)
		if err != nil {
			locale, theme, profile = "zh-Hans", "light", "base"
		}
		writeJSON(w, 200, map[string]any{
			"userId": user, "locale": locale, "theme": theme, "contentProfile": profile,
		}, true)
		return
	}
	if !csrfOK(r) {
		writeErr(w, http.StatusForbidden, "CSRF", "csrf", nil)
		return
	}
	var body struct {
		Locale         string `json:"locale"`
		Theme          string `json:"theme"`
		ContentProfile string `json:"contentProfile"`
	}
	if err := decodeLoose(r, &body); err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	locale := body.Locale
	switch locale {
	case "zh-Hans", "zh-Hant", "en", "ja":
	default:
		locale = "zh-Hans"
	}
	theme := "light"
	if body.Theme == "dark" {
		theme = "dark"
	}
	profile := "base"
	if body.ContentProfile == "iceborne" {
		profile = "iceborne"
	}
	_, err := s.Store.Pool.Exec(r.Context(), `
		INSERT INTO account_preferences (user_id, locale, theme, content_profile, updated_at)
		VALUES ($1,$2,$3,$4, now())
		ON CONFLICT (user_id) DO UPDATE SET
		  locale=EXCLUDED.locale, theme=EXCLUDED.theme, content_profile=EXCLUDED.content_profile, updated_at=now()
	`, user, locale, theme, profile)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, map[string]any{"userId": user, "locale": locale, "theme": theme, "contentProfile": profile}, true)
}

type dayCount struct {
	Day   string `json:"day"`
	Count int    `json:"count"`
}

type namedCount struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Count int    `json:"count"`
}

type cohortRow struct {
	Day    string `json:"day"`
	Size   int    `json:"size,omitempty"`
	D1     int    `json:"d1,omitempty"`
	D7     int    `json:"d7,omitempty"`
	Hidden bool   `json:"hidden"`
}

type metricsReport struct {
	From             string       `json:"from"`
	To               string       `json:"to"`
	Threshold        int          `json:"threshold"`
	NewAccounts      []dayCount   `json:"newAccounts"`
	ActiveVisitors   []dayCount   `json:"activeVisitors"`
	Retention        []cohortRow  `json:"retention"`
	Games            []namedCount `json:"games"`
	Weapons          []namedCount `json:"weapons"`
	Monsters         []namedCount `json:"monsters"`
	Styles           []namedCount `json:"styles"`
	Searches         []namedCount `json:"searches"`
	PublicBuilds     []namedCount `json:"publicBuilds"`
	NewVisitors      int          `json:"newVisitors"`
	Converted        int          `json:"converted"`
	ConversionHidden bool         `json:"conversionHidden"`
	AIRecords        int          `json:"aiRecords"`
	AICounted        int          `json:"aiCounted"`
	AIDailyUsed      int          `json:"aiDailyUsed"`
	AIDailyPresent   bool         `json:"aiDailyPresent"`
	AIMonthlyUsed    int          `json:"aiMonthlyUsed"`
	SyncUsedBytes    int64        `json:"syncUsedBytes"`
	SyncQuotaBytes   int64        `json:"syncQuotaBytes"`
}

func parseRange(r *http.Request) (time.Time, time.Time, error) {
	now := time.Now().UTC()
	endDay := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	start := endDay.AddDate(0, 0, -27)
	end := endDay.AddDate(0, 0, 1)
	if raw := r.URL.Query().Get("from"); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		start = t.UTC()
	}
	if raw := r.URL.Query().Get("to"); raw != "" {
		t, err := time.Parse("2006-01-02", raw)
		if err != nil {
			return time.Time{}, time.Time{}, err
		}
		end = t.UTC().AddDate(0, 0, 1)
	}
	if !start.Before(end) || end.Sub(start) > 366*24*time.Hour {
		return time.Time{}, time.Time{}, strconv.ErrRange
	}
	return start, end, nil
}

func (s *Server) loadMetrics(ctx context.Context, start, end time.Time) (metricsReport, error) {
	k := analyticsK()
	rep := metricsReport{
		From: start.Format("2006-01-02"), To: end.AddDate(0, 0, -1).Format("2006-01-02"), Threshold: k,
		NewAccounts: []dayCount{}, ActiveVisitors: []dayCount{}, Retention: []cohortRow{},
		Games: []namedCount{}, Weapons: []namedCount{}, Monsters: []namedCount{},
		Styles: []namedCount{}, Searches: []namedCount{}, PublicBuilds: []namedCount{},
	}
	newMap := map[string]int{}
	rows, err := s.Store.Pool.Query(ctx, `
		SELECT (created_at AT TIME ZONE 'UTC')::date, count(*)
		FROM accounts WHERE created_at >= $1 AND created_at < $2
		GROUP BY 1
	`, start, end)
	if err != nil {
		return rep, err
	}
	for rows.Next() {
		var day time.Time
		var n int
		if err := rows.Scan(&day, &n); err != nil {
			rows.Close()
			return rep, err
		}
		newMap[day.Format("2006-01-02")] = n
	}
	rows.Close()
	activeMap := map[string]int{}
	rows, err = s.Store.Pool.Query(ctx, `
		SELECT (occurred_at AT TIME ZONE 'UTC')::date, count(DISTINCT visitor_id)
		FROM analytics_events WHERE occurred_at >= $1 AND occurred_at < $2
		GROUP BY 1
	`, start, end)
	if err != nil {
		return rep, err
	}
	for rows.Next() {
		var day time.Time
		var n int
		if err := rows.Scan(&day, &n); err != nil {
			rows.Close()
			return rep, err
		}
		activeMap[day.Format("2006-01-02")] = n
	}
	rows.Close()
	for d := start; d.Before(end); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		rep.NewAccounts = append(rep.NewAccounts, dayCount{Day: key, Count: newMap[key]})
		rep.ActiveVisitors = append(rep.ActiveVisitors, dayCount{Day: key, Count: activeMap[key]})
	}
	rows, err = s.Store.Pool.Query(ctx, `
		WITH cohort AS (
		  SELECT id, (first_seen_at AT TIME ZONE 'UTC')::date AS day
		  FROM visitors
		  WHERE first_seen_at >= $1 AND first_seen_at < $2
		)
		SELECT c.day, count(*)::int,
		  count(*) FILTER (WHERE EXISTS (
		    SELECT 1 FROM analytics_events e
		    WHERE e.visitor_id = c.id AND (e.occurred_at AT TIME ZONE 'UTC')::date = c.day + 1
		  ))::int,
		  count(*) FILTER (WHERE EXISTS (
		    SELECT 1 FROM analytics_events e
		    WHERE e.visitor_id = c.id AND (e.occurred_at AT TIME ZONE 'UTC')::date = c.day + 7
		  ))::int
		FROM cohort c GROUP BY c.day ORDER BY c.day
	`, start, end)
	if err != nil {
		return rep, err
	}
	for rows.Next() {
		var day time.Time
		var size, d1, d7 int
		if err := rows.Scan(&day, &size, &d1, &d7); err != nil {
			rows.Close()
			return rep, err
		}
		row := cohortRow{Day: day.Format("2006-01-02"), Hidden: size < k}
		if !row.Hidden {
			row.Size, row.D1, row.D7 = size, d1, d7
		}
		rep.Retention = append(rep.Retention, row)
	}
	rows.Close()
	rows, err = s.Store.Pool.Query(ctx, `
		SELECT CASE
		  WHEN game_id = 'wilds' THEN 'wilds'
		  WHEN game_id = 'world' AND content_profile = 'iceborne' THEN 'iceborne'
		  WHEN game_id = 'world' THEN 'world'
		  ELSE ''
		END AS bucket, count(*)::int
		FROM analytics_events
		WHERE occurred_at >= $1 AND occurred_at < $2
		  AND event_type IN ('page_view','catalog_view','build_generate','search')
		  AND game_id IN ('world','wilds')
		GROUP BY 1
	`, start, end)
	if err != nil {
		return rep, err
	}
	labels := map[string]string{"world": "世界", "iceborne": "冰原", "wilds": "荒野"}
	for rows.Next() {
		var key string
		var n int
		if err := rows.Scan(&key, &n); err != nil {
			rows.Close()
			return rep, err
		}
		if key == "" || n < k {
			continue
		}
		rep.Games = append(rep.Games, namedCount{Key: key, Label: labels[key], Count: n})
	}
	rows.Close()
	if err := s.grouped(ctx, &rep.Weapons, k, `
		SELECT entry_id, count(*)::int FROM (
		  SELECT CASE WHEN event_type = 'build_generate' THEN weapon_id ELSE entry_id END AS entry_id
		  FROM analytics_events
		  WHERE occurred_at >= $1 AND occurred_at < $2
		    AND ((event_type = 'catalog_view' AND kind = 'weapon' AND entry_id <> '')
		      OR (event_type = 'build_generate' AND weapon_id <> ''))
		) s GROUP BY 1 HAVING count(*) >= $3 ORDER BY count(*) DESC LIMIT 12
	`, start, end); err != nil {
		return rep, err
	}
	if err := s.grouped(ctx, &rep.Monsters, k, `
		SELECT entry_id, count(*)::int FROM (
		  SELECT CASE WHEN event_type = 'build_generate' THEN monster_id ELSE entry_id END AS entry_id
		  FROM analytics_events
		  WHERE occurred_at >= $1 AND occurred_at < $2
		    AND ((event_type = 'catalog_view' AND kind = 'monster' AND entry_id <> '')
		      OR (event_type = 'build_generate' AND monster_id <> ''))
		) s WHERE entry_id <> '' GROUP BY 1 HAVING count(*) >= $3 ORDER BY count(*) DESC LIMIT 12
	`, start, end); err != nil {
		return rep, err
	}
	if err := s.grouped(ctx, &rep.Styles, k, `
		SELECT style, count(*)::int
		FROM analytics_events, jsonb_array_elements_text(styles) AS style
		WHERE event_type = 'build_generate' AND occurred_at >= $1 AND occurred_at < $2
		GROUP BY 1 HAVING count(*) >= $3 ORDER BY count(*) DESC LIMIT 12
	`, start, end); err != nil {
		return rep, err
	}
	if err := s.grouped(ctx, &rep.Searches, k, `
		SELECT query_norm, count(*)::int FROM analytics_events
		WHERE event_type = 'search' AND query_norm <> '' AND occurred_at >= $1 AND occurred_at < $2
		GROUP BY 1 HAVING count(*) >= $3 ORDER BY count(*) DESC LIMIT 12
	`, start, end); err != nil {
		return rep, err
	}
	rows, err = s.Store.Pool.Query(ctx, `
		SELECT e.public_id, count(*)::int, coalesce(max(p.title), e.public_id)
		FROM analytics_events e
		LEFT JOIN public_builds p ON p.id = e.public_id
		WHERE e.occurred_at >= $1 AND e.occurred_at < $2 AND e.public_id <> ''
		  AND e.event_type IN ('build_share','page_view')
		GROUP BY e.public_id HAVING count(*) >= $3
		ORDER BY count(*) DESC LIMIT 12
	`, start, end, k)
	if err != nil {
		return rep, err
	}
	for rows.Next() {
		var id, title string
		var n int
		if err := rows.Scan(&id, &n, &title); err != nil {
			rows.Close()
			return rep, err
		}
		rep.PublicBuilds = append(rep.PublicBuilds, namedCount{Key: id, Label: title, Count: n})
	}
	rows.Close()
	if err := s.Store.Pool.QueryRow(ctx, `
		SELECT
		  count(*) FILTER (WHERE first_seen_at >= $1 AND first_seen_at < $2)::int,
		  count(*) FILTER (WHERE user_id IS NOT NULL AND linked_at >= $1 AND linked_at < $2)::int
		FROM visitors
	`, start, end).Scan(&rep.NewVisitors, &rep.Converted); err != nil {
		return rep, err
	}
	if rep.NewVisitors < k {
		rep.ConversionHidden = true
		rep.NewVisitors = 0
		rep.Converted = 0
	}
	if err := s.Store.Pool.QueryRow(ctx, `
		SELECT count(*)::int, count(*) FILTER (WHERE counted)::int
		FROM ai_usage_log WHERE occurred_at >= $1 AND occurred_at < $2
	`, start, end).Scan(&rep.AIRecords, &rep.AICounted); err != nil {
		return rep, err
	}
	var daily *string
	if err := s.Store.Pool.QueryRow(ctx, `SELECT to_regclass('public.ai_daily')::text`).Scan(&daily); err != nil {
		return rep, err
	}
	if daily != nil {
		rep.AIDailyPresent = true
		_ = s.Store.Pool.QueryRow(ctx, `
			SELECT coalesce(sum(used),0)::int FROM ai_daily WHERE day >= $1::date AND day < $2::date
		`, start, end).Scan(&rep.AIDailyUsed)
		fromMonth := start.Format("2006-01")
		toMonth := end.AddDate(0, 0, -1).Format("2006-01")
		_ = s.Store.Pool.QueryRow(ctx, `
			SELECT coalesce(sum(used),0)::int FROM ai_monthly WHERE month >= $1 AND month <= $2
		`, fromMonth, toMonth).Scan(&rep.AIMonthlyUsed)
	}
	_ = s.Store.Pool.QueryRow(ctx, `
		SELECT coalesce(sum(used_bytes),0), coalesce(sum(quota_bytes),0) FROM entitlements
	`).Scan(&rep.SyncUsedBytes, &rep.SyncQuotaBytes)
	return rep, nil
}

func (s *Server) grouped(ctx context.Context, dest *[]namedCount, k int, query string, start, end time.Time) error {
	rows, err := s.Store.Pool.Query(ctx, query, start, end, k)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var key string
		var n int
		if err := rows.Scan(&key, &n); err != nil {
			return err
		}
		*dest = append(*dest, namedCount{Key: key, Label: key, Count: n})
	}
	return rows.Err()
}

func (s *Server) adminMetrics(w http.ResponseWriter, r *http.Request) {
	if !s.isAdmin(r) {
		s.denyAdmin(w, r)
		return
	}
	start, end, err := parseRange(r)
	if err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	rep, err := s.loadMetrics(r.Context(), start, end)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	writeJSON(w, 200, rep, true)
}

func (s *Server) adminPage(w http.ResponseWriter, r *http.Request) {
	if !s.isAdmin(r) {
		s.denyAdmin(w, r)
		return
	}
	start, end, err := parseRange(r)
	if err != nil {
		writeErr(w, http.StatusUnprocessableEntity, "VALIDATION", "validation", nil)
		return
	}
	rep, err := s.loadMetrics(r.Context(), start, end)
	if err != nil {
		writeErr(w, 500, "INTERNAL", "internal", nil)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Robots-Tag", "noindex")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(renderAdmin(rep)))
}

func (s *Server) privacyPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=300")
	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}
	w.WriteHeader(http.StatusOK)
	page := strings.ReplaceAll(privacyHTML, "{{retention}}", strconv.Itoa(retentionDays()))
	page = strings.ReplaceAll(page, "{{threshold}}", strconv.Itoa(analyticsK()))
	_, _ = w.Write([]byte(page))
}

func renderAdmin(rep metricsReport) string {
	var b strings.Builder
	b.WriteString(adminHead)
	b.WriteString(`<form method="get" action="/admin" class="range">`)
	b.WriteString(`<label>从 <input type="date" name="from" value="` + html.EscapeString(rep.From) + `"></label>`)
	b.WriteString(`<label>到 <input type="date" name="to" value="` + html.EscapeString(rep.To) + `"></label>`)
	b.WriteString(`<button type="submit">查看</button></form>`)
	b.WriteString(`<p class="meta">分组少于 ` + strconv.Itoa(rep.Threshold) + ` 时不显示该组。这是本机数据库里的聚合，不是已上线的运营报表。</p>`)
	b.WriteString(`<section class="card"><h2>新增与活跃</h2>`)
	b.WriteString(lineChart(rep.NewAccounts, rep.ActiveVisitors))
	b.WriteString(`<table><thead><tr><th>日期</th><th>新账户</th><th>活跃访客</th></tr></thead><tbody>`)
	for i := range rep.NewAccounts {
		b.WriteString(`<tr><td>` + html.EscapeString(rep.NewAccounts[i].Day) + `</td><td>` + strconv.Itoa(rep.NewAccounts[i].Count) + `</td><td>` + strconv.Itoa(rep.ActiveVisitors[i].Count) + `</td></tr>`)
	}
	b.WriteString(`</tbody></table></section>`)
	b.WriteString(`<section class="card"><h2>留存</h2><p class="meta">同一天第一次出现的访客里，次日和第 7 天还有埋点的人数。小样本整行隐藏。</p>`)
	b.WriteString(`<table><thead><tr><th>首次出现</th><th>人数</th><th>次日</th><th>第 7 天</th></tr></thead><tbody>`)
	if len(rep.Retention) == 0 {
		b.WriteString(`<tr><td colspan="4">这段时间没有访客</td></tr>`)
	}
	for _, row := range rep.Retention {
		if row.Hidden {
			b.WriteString(`<tr><td>` + html.EscapeString(row.Day) + `</td><td colspan="3">样本不足，已隐藏</td></tr>`)
			continue
		}
		b.WriteString(`<tr><td>` + html.EscapeString(row.Day) + `</td><td>` + strconv.Itoa(row.Size) + `</td><td>` + strconv.Itoa(row.D1) + `</td><td>` + strconv.Itoa(row.D7) + `</td></tr>`)
	}
	b.WriteString(`</tbody></table></section>`)
	b.WriteString(`<div class="grid">`)
	writeBars(&b, "作品", rep.Games)
	writeBars(&b, "武器", rep.Weapons)
	writeBars(&b, "目标怪物", rep.Monsters)
	writeBars(&b, "玩法风格", rep.Styles)
	b.WriteString(`</div>`)
	b.WriteString(`<section class="card"><h2>访客转会员</h2>`)
	if rep.ConversionHidden {
		b.WriteString(`<p>样本不足，已隐藏。</p>`)
	} else {
		b.WriteString(`<p>新访客 <strong>` + strconv.Itoa(rep.NewVisitors) + `</strong>，其中这段时间关联到账户的 <strong>` + strconv.Itoa(rep.Converted) + `</strong>。</p>`)
		b.WriteString(`<p class="meta">关联发生在同一台浏览器带着匿名 id 登录之后。不是付费转化。本站没有支付。</p>`)
	}
	b.WriteString(`</section>`)
	b.WriteString(`<section class="card"><h2>AI 使用与额度</h2><ul>`)
	b.WriteString(`<li>结构化记录 ` + strconv.Itoa(rep.AIRecords) + ` 条，其中记为消耗次数的 ` + strconv.Itoa(rep.AICounted) + ` 条。原句不在库里。</li>`)
	if rep.AIDailyPresent {
		b.WriteString(`<li>听懂次数账本：所选日期合计 ` + strconv.Itoa(rep.AIDailyUsed) + `，涉及月份合计 ` + strconv.Itoa(rep.AIMonthlyUsed) + `。</li>`)
	} else {
		b.WriteString(`<li>听懂次数账本还没有表。</li>`)
	}
	b.WriteString(`<li>同步空间当前已用 ` + strconv.FormatInt(rep.SyncUsedBytes, 10) + ` / ` + strconv.FormatInt(rep.SyncQuotaBytes, 10) + ` 字节。这是开发额度，不是模型售价，也不按上面的日期裁剪。</li>`)
	b.WriteString(`</ul></section>`)
	b.WriteString(`<div class="grid">`)
	writeBars(&b, "热门搜索", rep.Searches)
	writeBars(&b, "热门公开配装", rep.PublicBuilds)
	b.WriteString(`</div>`)
	b.WriteString(`<p class="foot"><a href="/privacy">隐私说明</a></p></main></body></html>`)
	return b.String()
}

func writeBars(b *strings.Builder, title string, rows []namedCount) {
	b.WriteString(`<section class="card"><h2>` + html.EscapeString(title) + `</h2>`)
	if len(rows) == 0 {
		b.WriteString(`<p class="meta">没有达到阈值的分组。</p></section>`)
		return
	}
	max := 1
	for _, row := range rows {
		if row.Count > max {
			max = row.Count
		}
	}
	b.WriteString(`<ul class="bars">`)
	for _, row := range rows {
		label := row.Label
		if label == "" {
			label = row.Key
		}
		width := row.Count * 100 / max
		if width < 4 {
			width = 4
		}
		b.WriteString(`<li><span>` + html.EscapeString(label) + `</span><span class="track"><span class="fill" style="width:` + strconv.Itoa(width) + `%"></span></span><span class="num">` + strconv.Itoa(row.Count) + `</span></li>`)
	}
	b.WriteString(`</ul></section>`)
}

func lineChart(newer, active []dayCount) string {
	if len(newer) == 0 {
		return ""
	}
	max := 1
	for i := range newer {
		if newer[i].Count > max {
			max = newer[i].Count
		}
		if active[i].Count > max {
			max = active[i].Count
		}
	}
	const width = 640.0
	const height = 160.0
	const left = 28.0
	const top = 12.0
	plotW := width - left - 8
	plotH := height - top - 22
	point := func(series []dayCount, i int) (float64, float64) {
		x := left
		if len(series) > 1 {
			x = left + plotW*float64(i)/float64(len(series)-1)
		}
		y := top + plotH - plotH*float64(series[i].Count)/float64(max)
		return x, y
	}
	poly := func(series []dayCount) string {
		var parts []string
		for i := range series {
			x, y := point(series, i)
			parts = append(parts, strconv.FormatFloat(x, 'f', 1, 64)+","+strconv.FormatFloat(y, 'f', 1, 64))
		}
		return strings.Join(parts, " ")
	}
	var b strings.Builder
	b.WriteString(`<svg viewBox="0 0 640 180" role="img" aria-label="新增账户与活跃访客">`)
	b.WriteString(`<line x1="28" y1="12" x2="28" y2="150" stroke="rgba(45,27,8,0.14)"/>`)
	b.WriteString(`<line x1="28" y1="150" x2="632" y2="150" stroke="rgba(45,27,8,0.14)"/>`)
	b.WriteString(`<polyline fill="none" stroke="#376ac9" stroke-width="2" points="` + poly(active) + `"/>`)
	b.WriteString(`<polyline fill="none" stroke="#991e45" stroke-width="2" points="` + poly(newer) + `"/>`)
	b.WriteString(`</svg>`)
	b.WriteString(`<p class="legend"><span class="swatch accent"></span>新账户 <span class="swatch bar"></span>活跃访客</p>`)
	return b.String()
}

const adminHead = `<!DOCTYPE html>
<html lang="zh-Hans" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>运营看板</title>
<style>
@font-face { font-family: "Noto Sans SC"; src: url("/assets/analytics/NotoSansSC-400.ttf") format("truetype"); font-weight: 400; font-display: swap; }
:root { --paper:#d9cbaf; --paper-bar:#efe6d4; --card:#e1d7c4; --sheet:#f4efe4; --ink:#2d1b08; --meta:#5c5140; --accent:#991e45; --on-accent:#fff; --bar:#376ac9; --line:rgba(45,27,8,.14); }
* { box-sizing: border-box; }
body { margin:0; background:var(--paper); color:var(--ink); font:15px/1.55 "Noto Sans SC", sans-serif; }
header { background:var(--paper-bar); padding:16px 24px; }
header h1 { margin:0; font-size:20px; line-height:1.25; }
header p { margin:4px 0 0; color:var(--meta); font-size:13px; }
main { max-width:1120px; margin:0 auto; padding:24px; }
.range { display:flex; flex-wrap:wrap; gap:12px; align-items:end; margin-bottom:12px; }
label { font-size:13px; color:var(--meta); }
input[type=date] { display:block; margin-top:4px; height:40px; border:0; border-radius:999px; background:var(--sheet); color:var(--ink); padding:0 14px; font:inherit; }
button { height:32px; min-width:96px; border:0; border-radius:999px; background:var(--accent); color:var(--on-accent); font:600 14px/1 "Noto Sans SC", sans-serif; padding:0 16px; }
.card { background:var(--card); border-radius:2px; margin:0 0 12px; overflow:hidden; }
.card h2 { margin:0; background:var(--ink); color:#e5d9c6; font-size:16px; font-weight:600; line-height:40px; padding:0 14px; }
.card p, .card ul, .card table { margin:12px 14px; }
.meta { color:var(--meta); font-size:13px; }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
svg { width:100%; height:auto; background:var(--sheet); }
table { width:calc(100% - 28px); border-collapse:collapse; font-size:13px; }
th { text-align:left; color:var(--meta); font-weight:600; }
td, th { border-bottom:1px solid var(--line); padding:6px 4px; }
.legend { font-size:13px; color:var(--meta); }
.swatch { display:inline-block; width:12px; height:12px; margin:0 4px 0 8px; vertical-align:middle; }
.swatch.accent { background:#991e45; }
.swatch.bar { background:#376ac9; }
.bars { list-style:none; padding:0; }
.bars li { display:grid; grid-template-columns:minmax(0,1.2fr) minmax(80px,2fr) auto; gap:8px; align-items:center; margin:8px 0; }
.track { background:var(--sheet); height:10px; border-radius:999px; }
.fill { display:block; height:10px; background:var(--accent); border-radius:999px; }
.num { font-weight:600; }
.foot { margin:8px 0 24px; }
a { color:var(--accent); }
@media (max-width: 719px) {
  header, main { padding-left:12px; padding-right:12px; }
  .grid { grid-template-columns:1fr; }
  .bars li { grid-template-columns:1fr; }
}
</style>
</head>
<body>
<header><h1>运营看板</h1><p>只给指定的管理员。访客和普通会员看不到这一页。</p></header>
<main>
`

const notFoundHTML = `<!DOCTYPE html>
<html lang="zh-Hans" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>没有这个页面</title>
<style>
@font-face { font-family: "Noto Sans SC"; src: url("/assets/analytics/NotoSansSC-400.ttf") format("truetype"); font-weight: 400; font-display: swap; }
body { margin:0; min-height:100vh; display:grid; place-items:center; background:#d9cbaf; color:#2d1b08; font:15px/1.55 "Noto Sans SC", sans-serif; }
main { background:#e1d7c4; border-radius:2px; max-width:420px; }
h1 { margin:0; background:#2d1b08; color:#e5d9c6; font-size:16px; line-height:40px; padding:0 14px; }
p { margin:12px 14px; }
a { color:#991e45; }
</style>
</head>
<body><main><h1>没有这个页面</h1><p>这个地址没有公开内容。</p><p><a href="/">回首页</a></p></main></body></html>`

const privacyHTML = `<!DOCTYPE html>
<html lang="zh-Hans" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>隐私说明 · MH伙伴助手</title>
<style>
@font-face { font-family: "Noto Sans SC"; src: url("/assets/analytics/NotoSansSC-400.ttf") format("truetype"); font-weight: 400; font-display: swap; }
body { margin:0; background:#d9cbaf; color:#2d1b08; font:15px/1.55 "Noto Sans SC", sans-serif; }
header { background:#efe6d4; padding:16px 24px; }
h1 { margin:0; font-size:20px; }
main { max-width:760px; margin:0 auto; padding:24px; }
section { background:#e1d7c4; border-radius:2px; margin-bottom:12px; }
h2 { margin:0; background:#2d1b08; color:#e5d9c6; font-size:16px; font-weight:600; line-height:40px; padding:0 14px; }
p, li { margin:12px 14px; }
ul { padding-left:18px; }
.meta { color:#5c5140; font-size:13px; }
a { color:#991e45; }
@media (max-width: 719px) { header, main { padding-left:12px; padding-right:12px; } }
</style>
</head>
<body>
<header><h1>隐私说明</h1><p class="meta">MH伙伴助手还没有公网站点。下面写的是这套代码准备怎么处理数据，不是已经上线的承诺。</p></header>
<main>
<section><h2>收集什么</h2>
<ul>
<li>账户：开发登录写下的用户 id 和显示名。没有密码，也没有手机号。</li>
<li>个人配装、装饰品和护石库存：登录之后随同步写入数据库。库存只记条目 id、种类和数量。</li>
<li>偏好：界面语言、浅色或深色、本体或冰原。未登录时只留在这台浏览器。</li>
<li>AI 使用：作品、内容档、武器和怪物的条目 id、风格短词、相关条目 id、是否记一次额度。默认不保存你打的那句话。</li>
<li>匿名埋点：随机访客 id、页面路径、搜索词、打开过的作品或武器或怪物、配装生成和分享的条目 id。访客 id 写在 Cookie <code>mh_anon</code> 里。</li>
</ul>
</section>
<section><h2>不收集什么</h2>
<ul>
<li>不保存 IP 地址的明文，也不把 IP 写进访客 id。</li>
<li>AI 原句默认不落库。排错开关不在这一版里打开。</li>
<li>不把提示词写成「用于训练模型」。</li>
<li>看板不展示单个猎人的句子、配装正文或库存清单。</li>
</ul>
</section>
<section><h2>用来做什么</h2>
<p>账户数据用来在登录后的设备之间同步你自己的配装、库存和偏好。埋点和 AI 记录只做成聚合：新增和活跃、留存、作品分布、武器和怪物、玩法风格、访客是否后来登录、AI 次数和同步空间、热门搜索、热门公开配装。</p>
</section>
<section><h2>保存多久</h2>
<p>账户、配装、库存和偏好保留到该账户还在。匿名埋点和 AI 结构化记录默认保留 {{retention}} 天，服务启动后清掉更早的行。会话 Cookie 大约 7 天。匿名访客 Cookie 大约 400 天；清除这台浏览器的站点数据会换一个新的访客 id。</p>
</section>
<section><h2>谁能看看板</h2>
<p>运营看板在 <a href="/admin">/admin</a>。服务端只放行环境变量或启动参数里点名的管理员。访客和普通会员打开页面或接口，得到 404。看板只画聚合。一个分组少于 {{threshold}} 时，这一组的名字和次数都不显示。</p>
<p class="meta">同步空间的字节数是开发环境的额度，不是会员价格。本站没有支付。</p>
</section>
<p><a href="/">回首页</a></p>
</main>
</body></html>`
