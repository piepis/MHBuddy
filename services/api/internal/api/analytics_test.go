package api

import (
	"context"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestAdminIDsFromEnvAndArgs(t *testing.T) {
	got := adminIDs(" hunter-a, ops ", []string{"mhbuddy", "--admin", "ada", "--admin=beau"})
	for _, id := range []string{"hunter-a", "ops", "ada", "beau"} {
		if _, ok := got[id]; !ok {
			t.Fatalf("missing %s in %#v", id, got)
		}
	}
}

func TestAnalyticsHiddenFromGuestsAndMembers(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	t.Setenv("MH_ADMINS", "hunter-a")
	for _, path := range []string{"/admin", "/v1/admin/metrics"} {
		res := do(t, srv, "GET", path, nil, "")
		if res.StatusCode != http.StatusNotFound {
			t.Fatalf("guest %s status %d", path, res.StatusCode)
		}
		res.Body.Close()
		member := login(t, srv, "hunter-b")
		res = do(t, srv, "GET", path, nil, member)
		if res.StatusCode != http.StatusNotFound {
			t.Fatalf("member %s status %d", path, res.StatusCode)
		}
		res.Body.Close()
	}
	admin := login(t, srv, "hunter-a")
	res := do(t, srv, "GET", "/admin", nil, admin)
	if res.StatusCode != 200 {
		t.Fatalf("admin page %d %s", res.StatusCode, readBody(t, res))
	}
	body := readBody(t, res)
	if !strings.Contains(body, "运营看板") || !strings.Contains(body, "新增与活跃") {
		t.Fatalf("dashboard missing sections")
	}
	res = do(t, srv, "GET", "/v1/admin/metrics", nil, admin)
	if res.StatusCode != 200 {
		t.Fatalf("metrics %d", res.StatusCode)
	}
	metrics := readJSON(t, res)
	if metrics["threshold"].(float64) != 5 {
		t.Fatalf("threshold %#v", metrics["threshold"])
	}
}

func TestCollectSkipsIPAndHidesSmallGroups(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	t.Setenv("MH_ADMINS", "hunter-a")
	t.Setenv("MH_ANALYTICS_K", "5")
	pool := openTestPool(t)
	defer pool.Close()
	var ipColumn bool
	err := pool.QueryRow(context.Background(), `
		SELECT EXISTS (
		  SELECT 1 FROM information_schema.columns
		  WHERE table_name IN ('analytics_events','visitors','ai_usage_log')
		    AND column_name ILIKE '%ip%'
		)
	`).Scan(&ipColumn)
	if err != nil {
		t.Fatal(err)
	}
	if ipColumn {
		t.Fatal("ip column exists")
	}
	day := time.Now().UTC().Format("2006-01-02")
	for i := 0; i < 6; i++ {
		res := do(t, srv, "POST", "/v1/analytics/collect", map[string]any{
			"type": "search", "query": "火龙", "gameId": "world", "contentProfile": "base",
			"path": "/g/world/entries", "at": day + "T03:00:00Z",
		}, visitorCookie(i))
		if res.StatusCode != 200 {
			t.Fatalf("search %d %s", res.StatusCode, readBody(t, res))
		}
		res.Body.Close()
	}
	for i := 0; i < 2; i++ {
		res := do(t, srv, "POST", "/v1/analytics/collect", map[string]any{
			"type": "search", "query": "  稀有矿  ", "gameId": "wilds", "at": day + "T04:00:00Z",
		}, visitorCookie(10+i))
		if res.StatusCode != 200 {
			t.Fatalf("small %d %s", res.StatusCode, readBody(t, res))
		}
		res.Body.Close()
	}
	admin := login(t, srv, "hunter-a")
	res := do(t, srv, "GET", "/v1/admin/metrics?from="+day+"&to="+day, nil, admin)
	metrics := readJSON(t, res)
	searches := metrics["searches"].([]any)
	if len(searches) != 1 {
		t.Fatalf("searches %#v", searches)
	}
	row := searches[0].(map[string]any)
	if row["key"] != "火龙" || row["count"].(float64) != 6 {
		t.Fatalf("row %#v", row)
	}
	games := metrics["games"].([]any)
	if len(games) != 1 || games[0].(map[string]any)["key"] != "world" {
		t.Fatalf("games %#v", games)
	}
}

func TestAIUsageDropsSentence(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	sentence := "SENTENCE-SHOULD-NOT-PERSIST-9f3a"
	res := do(t, srv, "POST", "/v1/ai/usage", map[string]any{
		"sentence": sentence, "prompt": sentence, "gameId": "world", "contentProfile": "iceborne",
		"weaponIds": []string{"fixture-iron-sword"}, "monsterIds": []string{"fixture-jagras"},
		"styles": []string{"会心", sentence}, "counted": true,
	}, visitorCookie(3))
	if res.StatusCode != 200 {
		t.Fatalf("usage %d %s", res.StatusCode, readBody(t, res))
	}
	res.Body.Close()
	pool := openTestPool(t)
	defer pool.Close()
	var blob string
	err := pool.QueryRow(context.Background(), `
		SELECT id::text || subject || game_id || content_profile || weapon_ids::text || monster_ids::text || styles::text || entry_ids::text
		FROM ai_usage_log
	`).Scan(&blob)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(blob, sentence) {
		t.Fatalf("sentence stored in %s", blob)
	}
	if !strings.Contains(blob, "fixture-iron-sword") || !strings.Contains(blob, "iceborne") || !strings.Contains(blob, "会心") {
		t.Fatalf("structured fields missing %s", blob)
	}
}

func TestPreferencesAndInventoryRoundTrip(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, "GET", "/v1/me/preferences", nil, "")
	if res.StatusCode != 401 {
		t.Fatalf("anon prefs %d", res.StatusCode)
	}
	res.Body.Close()
	cookie := login(t, srv, "hunter-a")
	res = do(t, srv, "PUT", "/v1/me/preferences", map[string]any{
		"locale": "ja", "theme": "dark", "contentProfile": "iceborne",
	}, cookie)
	if res.StatusCode != 200 {
		t.Fatalf("put %d %s", res.StatusCode, readBody(t, res))
	}
	res.Body.Close()
	res = do(t, srv, "GET", "/v1/me/preferences", nil, cookie)
	body := readJSON(t, res)
	if body["locale"] != "ja" || body["theme"] != "dark" || body["contentProfile"] != "iceborne" {
		t.Fatalf("prefs %#v", body)
	}
	op := map[string]any{
		"opId": "talisman-1", "recordType": "inventory", "recordId": "fixture-charm", "gameId": "world",
		"kind": "talisman", "entryId": "fixture-charm", "baseRevision": 0, "action": "upsert",
		"payload": map[string]any{"quantity": 1, "kind": "talisman"},
	}
	jewel := map[string]any{
		"opId": "jewel-1", "recordType": "inventory", "recordId": "fixture-attack-jewel", "gameId": "world",
		"kind": "decoration", "entryId": "fixture-attack-jewel", "baseRevision": 0, "action": "upsert",
		"payload": map[string]any{"quantity": 2, "kind": "decoration"},
	}
	build := map[string]any{
		"opId": "build-1", "recordType": "build", "recordId": "local-1", "gameId": "world",
		"baseRevision": 0, "action": "upsert", "payload": map[string]any{"title": "我的配装", "fixture": true},
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{op, jewel, build}}, cookie)
	pushed := readJSON(t, res)
	for _, raw := range pushed["results"].([]any) {
		if raw.(map[string]any)["status"] != "applied" {
			t.Fatalf("push %#v", pushed)
		}
	}
	res = do(t, srv, "GET", "/v1/sync/snapshot", nil, cookie)
	snap := readJSON(t, res)
	recs := snap["records"].([]any)
	if len(recs) != 3 {
		t.Fatalf("records %#v", recs)
	}
}

func TestPrivacyPage(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, "GET", "/privacy", nil, "")
	if res.StatusCode != 200 {
		t.Fatalf("privacy %d", res.StatusCode)
	}
	body := readBody(t, res)
	for _, part := range []string{"收集什么", "不收集什么", "保存多久", "不保存 IP", "默认不保存你打的那句话"} {
		if !strings.Contains(body, part) {
			t.Fatalf("missing %s", part)
		}
	}
}

func TestRetentionAndConversion(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	t.Setenv("MH_ADMINS", "hunter-a")
	t.Setenv("MH_ANALYTICS_K", "5")
	base := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		res := do(t, srv, "POST", "/v1/analytics/collect", map[string]any{
			"type": "page_view", "path": "/", "at": base.Format(time.RFC3339),
		}, visitorCookie(20+i))
		if res.StatusCode != 200 {
			t.Fatalf("cohort %d %s", res.StatusCode, readBody(t, res))
		}
		res.Body.Close()
		res = do(t, srv, "POST", "/v1/analytics/collect", map[string]any{
			"type": "page_view", "path": "/g/world/entries", "at": base.AddDate(0, 0, 1).Format(time.RFC3339),
		}, visitorCookie(20+i))
		res.Body.Close()
	}
	admin := login(t, srv, "hunter-a")
	res := do(t, srv, "POST", "/v1/analytics/collect", map[string]any{
		"type": "session", "path": "/me", "at": base.Format(time.RFC3339),
	}, admin+"; "+visitorCookie(30))
	if res.StatusCode != 200 {
		t.Fatalf("link %d %s", res.StatusCode, readBody(t, res))
	}
	res.Body.Close()
	res = do(t, srv, "GET", "/v1/admin/metrics?from=2026-11-01&to=2026-11-10", nil, admin)
	metrics := readJSON(t, res)
	rows := metrics["retention"].([]any)
	if len(rows) == 0 || rows[0].(map[string]any)["hidden"] == true {
		t.Fatalf("retention %#v", rows)
	}
	first := rows[0].(map[string]any)
	if first["d1"].(float64) != 5 {
		t.Fatalf("d1 %#v", first)
	}
	if metrics["conversionHidden"] == true {
		t.Fatal("conversion hidden")
	}
	if metrics["converted"].(float64) < 1 {
		t.Fatalf("converted %#v", metrics["converted"])
	}
}

func visitorCookie(n int) string {
	hexits := "0123456789abcdef"
	var b strings.Builder
	b.WriteString("mh_anon=")
	for i := 0; i < 32; i++ {
		b.WriteByte(hexits[(n+i)%16])
	}
	return b.String()
}

func readBody(t *testing.T, res *http.Response) string {
	t.Helper()
	defer res.Body.Close()
	buf, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return string(buf)
}

func openTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://ubuntu@127.0.0.1:5432/mhbuddy_test?sslmode=disable"
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	return pool
}
