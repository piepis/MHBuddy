package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"mhbuddy/services/api/internal/ai"
)

func testServer(t *testing.T) *httptest.Server {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://ubuntu@127.0.0.1:5432/mhbuddy_test?sslmode=disable"
	}
	ctx := context.Background()
	if err := EnsureDatabase(ctx, "postgres://ubuntu@127.0.0.1:5432/postgres?sslmode=disable", "mhbuddy_test"); err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	root := findRoot(t)
	mig, err := os.ReadFile(filepath.Join(root, "services", "api", "migrations", "001_player_records.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool, string(mig)); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `TRUNCATE TABLE reminder_jobs, reminder_subs, public_builds, articles, events, sync_ops, sync_log, player_records, sessions, entitlements, account_state, accounts RESTART IDENTITY CASCADE`); err != nil {
		t.Fatal(err)
	}
	content := filepath.Join(root, "content", "fixtures")
	if err := Seed(ctx, pool, content); err != nil {
		t.Fatal(err)
	}
	return httptest.NewServer(New(pool, true, content, ""))
}

func findRoot(t *testing.T) string {
	t.Helper()
	dir, _ := os.Getwd()
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "docs", "GROK_BUILD_SPEC.md")); err == nil {
			return dir
		}
		dir = filepath.Dir(dir)
	}
	t.Fatal("repo root")
	return ""
}

func do(t *testing.T, srv *httptest.Server, method, path string, body any, cookie string) *http.Response {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, srv.URL+path, rdr)
	if err != nil {
		t.Fatal(err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func readJSON(t *testing.T, res *http.Response) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.NewDecoder(res.Body).Decode(&m); err != nil {
		t.Fatal(err)
	}
	return m
}

func login(t *testing.T, srv *httptest.Server, user string) string {
	t.Helper()
	res := do(t, srv, "POST", "/v1/auth/session", map[string]string{"provider": "dev", "userId": user, "displayName": user}, "")
	if res.StatusCode != 200 {
		t.Fatalf("login %d", res.StatusCode)
	}
	for _, c := range res.Cookies() {
		if c.Name == "mh_session" {
			return c.Name + "=" + c.Value
		}
	}
	t.Fatal("no cookie")
	return ""
}

func TestAnonymousSyncRejected(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{}}, "")
	if res.StatusCode != 422 && res.StatusCode != 401 {
		t.Fatalf("status %d", res.StatusCode)
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []map[string]any{{"opId": "x", "recordType": "build", "recordId": "b1", "gameId": "world", "action": "upsert", "payload": map[string]any{"title": "a"}}}}, "")
	if res.StatusCode != 401 {
		t.Fatalf("anon sync %d", res.StatusCode)
	}
	body := readJSON(t, res)
	if body["code"] != "UNAUTHORIZED" {
		t.Fatalf("code %v", body["code"])
	}
}

func TestSyncRetryConflictQuotaAndCursor(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	cookie := login(t, srv, "hunter-a")
	op := map[string]any{
		"opId": "op-1", "recordType": "build", "recordId": "build-1", "gameId": "world",
		"baseRevision": 0, "action": "upsert", "payload": map[string]any{"title": "第一套"},
	}
	res := do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{op}}, cookie)
	body := readJSON(t, res)
	results := body["results"].([]any)
	first := results[0].(map[string]any)
	if first["status"] != "applied" || first["revision"].(float64) != 1 {
		t.Fatalf("first %#v", first)
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{op}}, cookie)
	body = readJSON(t, res)
	again := body["results"].([]any)[0].(map[string]any)
	if again["revision"].(float64) != 1 {
		t.Fatalf("retry wrote again %#v", again)
	}
	op["payload"] = map[string]any{"title": "别的内容"}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{op}}, cookie)
	body = readJSON(t, res)
	bad := body["results"].([]any)[0].(map[string]any)
	if bad["code"] != "IDEMPOTENCY_CONFLICT" {
		t.Fatalf("idem %#v", bad)
	}
	stale := map[string]any{
		"opId": "op-2", "recordType": "build", "recordId": "build-1", "gameId": "world",
		"baseRevision": 0, "action": "upsert", "payload": map[string]any{"title": "冲突"},
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{stale}}, cookie)
	body = readJSON(t, res)
	conf := body["results"].([]any)[0].(map[string]any)
	if conf["code"] != "REVISION_CONFLICT" {
		t.Fatalf("conflict %#v", conf)
	}
	del := map[string]any{
		"opId": "op-del", "recordType": "build", "recordId": "build-1", "gameId": "world",
		"baseRevision": 1, "action": "delete", "payload": map[string]any{},
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{del}}, cookie)
	body = readJSON(t, res)
	if body["results"].([]any)[0].(map[string]any)["status"] != "applied" {
		t.Fatalf("delete %#v", body)
	}
	revive := map[string]any{
		"opId": "op-revive", "recordType": "build", "recordId": "build-1", "gameId": "world",
		"baseRevision": 1, "action": "upsert", "payload": map[string]any{"title": "复活"},
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{revive}}, cookie)
	body = readJSON(t, res)
	rev := body["results"].([]any)[0].(map[string]any)
	if rev["code"] != "REVISION_CONFLICT" {
		t.Fatalf("delete won %#v", rev)
	}
	res = do(t, srv, "POST", "/v1/dev/compact", map[string]any{}, cookie)
	if res.StatusCode != 204 {
		t.Fatalf("compact %d", res.StatusCode)
	}
	res = do(t, srv, "GET", "/v1/sync/pull?cursor=0", nil, cookie)
	if res.StatusCode != 409 {
		t.Fatalf("cursor %d", res.StatusCode)
	}
	snap := do(t, srv, "GET", "/v1/sync/snapshot", nil, cookie)
	sb := readJSON(t, snap)
	if _, ok := sb["watermark"]; !ok {
		t.Fatal("snapshot")
	}
}

func TestQuotaAndIsolation(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	cookie := login(t, srv, "hunter-b")
	payload := map[string]any{"title": string(bytes.Repeat([]byte("x"), 500))}
	op := func(id string) map[string]any {
		return map[string]any{
			"opId": id, "recordType": "build", "recordId": id, "gameId": "wilds",
			"baseRevision": 0, "action": "upsert", "payload": payload,
		}
	}
	var wg sync.WaitGroup
	codes := make([]string, 2)
	var mu sync.Mutex
	for i, id := range []string{"q1", "q2"} {
		wg.Add(1)
		go func(i int, id string) {
			defer wg.Done()
			b, _ := json.Marshal(map[string]any{"ops": []any{op(id)}})
			req, _ := http.NewRequest("POST", srv.URL+"/v1/sync/push", bytes.NewReader(b))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Cookie", cookie)
			res, err := http.DefaultClient.Do(req)
			if err != nil {
				return
			}
			defer res.Body.Close()
			var body map[string]any
			_ = json.NewDecoder(res.Body).Decode(&body)
			status := ""
			if results, ok := body["results"].([]any); ok && len(results) > 0 {
				status, _ = results[0].(map[string]any)["status"].(string)
			}
			mu.Lock()
			codes[i] = status
			mu.Unlock()
		}(i, id)
	}
	wg.Wait()
	applied := 0
	for _, c := range codes {
		if c == "applied" {
			applied++
		}
	}
	if applied != 1 {
		t.Fatalf("quota race applied=%d codes=%v", applied, codes)
	}
	res := do(t, srv, "POST", "/v1/dev/entitlement", map[string]any{"planId": "downgraded", "quotaBytes": 100}, cookie)
	if res.StatusCode != 200 {
		t.Fatalf("downgrade %d", res.StatusCode)
	}
	snapRes := do(t, srv, "GET", "/v1/sync/snapshot", nil, cookie)
	snapBody := readJSON(t, snapRes)
	recs := snapBody["records"].([]any)
	if len(recs) != 1 {
		t.Fatalf("expected one build, %#v", recs)
	}
	kept := recs[0].(map[string]any)
	shrink := map[string]any{
		"opId": "shrink", "recordType": "build", "recordId": kept["recordId"], "gameId": "wilds",
		"baseRevision": int(kept["revision"].(float64)), "action": "delete", "payload": map[string]any{},
	}
	res = do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{shrink}}, cookie)
	body := readJSON(t, res)
	if body["results"].([]any)[0].(map[string]any)["status"] != "applied" {
		t.Fatalf("shrink %#v", body)
	}
	other := login(t, srv, "hunter-a")
	res = do(t, srv, "GET", "/v1/sync/snapshot", nil, other)
	snap := readJSON(t, res)
	recs = snap["records"].([]any)
	if len(recs) != 0 {
		t.Fatalf("cross account %#v", recs)
	}
}

func TestFavoritesSeparateGames(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	cookie := login(t, srv, "hunter-a")
	for _, game := range []string{"world", "wilds"} {
		op := map[string]any{
			"opId": "fav-" + game, "recordType": "favorite", "recordId": "fav-" + game, "gameId": game,
			"kind": "material", "entryId": "same-name", "baseRevision": 0, "action": "upsert", "payload": map[string]any{"entryId": "same-name"},
		}
		res := do(t, srv, "POST", "/v1/sync/push", map[string]any{"ops": []any{op}}, cookie)
		body := readJSON(t, res)
		if body["results"].([]any)[0].(map[string]any)["status"] != "applied" {
			t.Fatalf("fav %s %#v", game, body)
		}
	}
}

func TestPublicBuildsAndEvents(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, "GET", "/v1/public-builds/pub-fixture-wilds-1", nil, "")
	if res.StatusCode != 200 {
		t.Fatalf("public %d", res.StatusCode)
	}
	body := readJSON(t, res)
	if body["status"] != "published" {
		t.Fatalf("status %#v", body["status"])
	}
	res = do(t, srv, "GET", "/builds/does-not-exist", nil, "")
	if res.StatusCode != 404 {
		t.Fatalf("unknown page %d", res.StatusCode)
	}
	cookie := login(t, srv, "hunter-a")
	res = do(t, srv, "POST", "/v1/public-builds", map[string]any{
		"title": "猎人发布", "gameId": "world", "weaponType": "sword", "rarity": 2,
		"snapshot": map[string]any{"title": "猎人发布", "gameId": "world"},
	}, cookie)
	if res.StatusCode != 201 {
		t.Fatalf("publish %d", res.StatusCode)
	}
	pub := readJSON(t, res)
	id := pub["id"].(string)
	res = do(t, srv, "GET", "/v1/events?gameId=world&q="+urlQuery("夹具赏金"), nil, "")
	ev := readJSON(t, res)
	list := ev["events"].([]any)
	if len(list) != 1 || list[0].(map[string]any)["id"] != "fixture-event-ancient" {
		t.Fatalf("name search %#v", list)
	}
	res = do(t, srv, "GET", "/v1/events?gameId=world&reward="+urlQuery("夹具古代树果实"), nil, "")
	ev = readJSON(t, res)
	list = ev["events"].([]any)
	if len(list) != 1 || list[0].(map[string]any)["id"] != "fixture-event-ancient" {
		t.Fatalf("reward search %#v", list)
	}
	res = do(t, srv, "POST", "/v1/reminders/subscriptions", map[string]any{"eventId": "fixture-event-ancient", "platformId": "pc", "kind": "start", "revokeToken": "tok-1"}, "")
	if res.StatusCode != 201 {
		t.Fatalf("sub %d", res.StatusCode)
	}
	start := time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC)
	res = do(t, srv, "POST", "/v1/dev/events/fixture-event-ancient", map[string]any{"startsAt": start, "status": "rescheduled"}, cookie)
	if res.StatusCode != 200 {
		t.Fatalf("reschedule %d", res.StatusCode)
	}
	res = do(t, srv, "GET", "/v1/dev/reminder-jobs?eventId=fixture-event-ancient", nil, "")
	jobs := readJSON(t, res)
	pending := 0
	for _, j := range jobs["jobs"].([]any) {
		if j.(map[string]any)["status"] == "pending" {
			pending++
		}
	}
	if pending != 1 {
		t.Fatalf("jobs after reschedule %#v", jobs)
	}
	res = do(t, srv, "GET", "/v1/events/fixture-event-ancient/calendar.ics", nil, "")
	raw, _ := io.ReadAll(res.Body)
	if !bytes.Contains(raw, []byte("UID:fixture-event-ancient@mhbuddy.local")) || !bytes.Contains(raw, []byte("SEQUENCE:")) {
		t.Fatalf("ics %s", raw)
	}
	res = do(t, srv, "POST", "/v1/dev/events/fixture-event-ancient", map[string]any{"status": "revoked"}, cookie)
	if res.StatusCode != 200 {
		t.Fatalf("revoke %d", res.StatusCode)
	}
	res = do(t, srv, "GET", "/v1/dev/reminder-jobs?eventId=fixture-event-ancient", nil, "")
	jobs = readJSON(t, res)
	for _, j := range jobs["jobs"].([]any) {
		if j.(map[string]any)["status"] == "pending" {
			t.Fatalf("job still pending %#v", jobs)
		}
	}
	res = do(t, srv, "DELETE", "/v1/public-builds/"+id, nil, cookie)
	if res.StatusCode != 204 {
		t.Fatalf("retract %d", res.StatusCode)
	}
	res = do(t, srv, "GET", "/v1/public-builds/"+id, nil, "")
	if res.StatusCode != 410 {
		t.Fatalf("retracted read %d", res.StatusCode)
	}
	gone := readJSON(t, res)
	if gone["code"] != "RETRACTED" || gone["details"] == nil {
		t.Fatalf("gone %#v", gone)
	}
	if _, ok := gone["snapshot"]; ok {
		t.Fatal("snapshot leaked")
	}
	res = do(t, srv, "GET", "/v1/public-builds/build-1", nil, "")
	if res.StatusCode != 404 {
		t.Fatalf("private id %d", res.StatusCode)
	}
	other := login(t, srv, "hunter-b")
	res = do(t, srv, "DELETE", "/v1/public-builds/pub-fixture-wilds-1", nil, other)
	if res.StatusCode != 403 {
		t.Fatalf("not owner %d", res.StatusCode)
	}
}

func TestPackManifest(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, "GET", "/v1/packs/latest?gameId=world&contentProfile=base&platformId=pc&patchId=fixture-p1&clientVersion=0.1.0", nil, "")
	if res.StatusCode != 200 {
		t.Fatalf("pack %d", res.StatusCode)
	}
	etag := res.Header.Get("ETag")
	req, _ := http.NewRequest("GET", srv.URL+"/v1/packs/latest?gameId=world&clientVersion=0.1.0", nil)
	req.Header.Set("If-None-Match", etag)
	res2, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res2.Body.Close()
	if res2.StatusCode != 304 {
		t.Fatalf("etag %d", res2.StatusCode)
	}
	res = do(t, srv, "GET", "/v1/packs/latest?gameId=world&clientVersion=0.0.1", nil, "")
	if res.StatusCode != 422 {
		t.Fatalf("client %d", res.StatusCode)
	}
}

func TestCsrfRejectsForeignOrigin(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	body := bytes.NewReader([]byte(`{"provider":"dev","userId":"csrf-user","displayName":"csrf-user"}`))
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/v1/auth/session", body)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "https://evil.example")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("foreign origin %d", res.StatusCode)
	}
	got := readJSON(t, res)
	if got["code"] != "CSRF" {
		t.Fatalf("code %#v", got["code"])
	}
	if cache := res.Header.Get("Cache-Control"); cache != "private, no-store" {
		t.Fatalf("cache %q", cache)
	}
}

func TestAnonymousEntitlementAndSameOriginLogin(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, http.MethodGet, "/v1/me/entitlement", nil, "")
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("anon entitlement %d", res.StatusCode)
	}
	if cache := res.Header.Get("Cache-Control"); cache != "private, no-store" {
		t.Fatalf("cache %q", cache)
	}
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/v1/auth/session", bytes.NewReader([]byte(`{"provider":"dev","userId":"hunter-a","displayName":"hunter-a"}`)))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", srv.URL)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("same origin login %d", res.StatusCode)
	}
}

func TestAIUnavailableWhenUnset(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	res := do(t, srv, http.MethodGet, "/v1/ai/status", nil, "")
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
	body := readJSON(t, res)
	if body["showButton"] != false || body["reason"] != "no_key" {
		t.Fatalf("status %#v", body)
	}
	res = do(t, srv, http.MethodPost, "/v1/ai/understand", map[string]string{"sentence": "秘密原句不要落库"}, "")
	if res.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("understand %d", res.StatusCode)
	}
	errBody := readJSON(t, res)
	if errBody["code"] != "AI_UNAVAILABLE" || strings.Contains(fmtSprint(errBody), "秘密原句") {
		t.Fatalf("body %#v", errBody)
	}
}

func TestFakeProviderQuotaDoesNotStoreSentence(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://ubuntu@127.0.0.1:5432/mhbuddy_test?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	mig, err := os.ReadFile(filepath.Join(findRoot(t), "services", "api", "migrations", "002_ai_usage.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool, string(mig)); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `TRUNCATE TABLE ai_daily, ai_monthly`); err != nil {
		t.Fatal(err)
	}
	content := filepath.Join(findRoot(t), "content", "fixtures")
	server := New(pool, true, content, "")
	server.AI = ai.New(ai.Config{
		Provider: "fake", Model: "fake", APIKey: "test-key", Fixture: true,
		GuestDaily: 3, MemberDaily: 1, MonthlyCap: 10,
	}, ai.Fake{}, ai.NewPGQuota(pool))
	live := httptest.NewServer(server)
	defer live.Close()

	sentence := "秘密原句不要落库 世界 铁刀 输出"
	req, err := http.NewRequest(http.MethodPost, live.URL+"/v1/ai/understand", bytes.NewReader([]byte(`{"sentence":"`+sentence+`"}`)))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-MH-AI-Voucher", "browser-voucher")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("guest fixture %d", res.StatusCode)
	}
	var guestRows int
	if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM ai_daily WHERE subject LIKE 'guest:%'`).Scan(&guestRows); err != nil {
		t.Fatal(err)
	}
	if guestRows != 0 {
		t.Fatalf("guest charged %d", guestRows)
	}

	cookie := login(t, live, "hunter-a")
	res = do(t, live, http.MethodPost, "/v1/ai/understand", map[string]string{"sentence": sentence}, cookie)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("member %d", res.StatusCode)
	}
	understood := readJSON(t, res)
	if understood["gameId"] != "world" || strings.Contains(fmtSprint(understood), "秘密原句") {
		t.Fatalf("understood %#v", understood)
	}
	res = do(t, live, http.MethodPost, "/v1/ai/understand", map[string]string{"sentence": sentence}, cookie)
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("cap %d", res.StatusCode)
	}
	var stored string
	if err := pool.QueryRow(ctx, `SELECT COALESCE(string_agg(subject || ' ' || used::text, ','), '') FROM ai_daily`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != "user:hunter-a 1" {
		t.Fatalf("daily %q", stored)
	}
	var cols string
	if err := pool.QueryRow(ctx, `SELECT COALESCE(string_agg(column_name, ',' ORDER BY column_name), '') FROM information_schema.columns WHERE table_name IN ('ai_daily','ai_monthly')`).Scan(&cols); err != nil {
		t.Fatal(err)
	}
	for _, name := range strings.Split(cols, ",") {
		switch name {
		case "subject", "day", "used", "month":
		default:
			t.Fatalf("unexpected column %s in %s", name, cols)
		}
	}
	if strings.Contains(stored, "秘密原句") || strings.Contains(cols, "sentence") || strings.Contains(cols, "ip") {
		t.Fatalf("pii stored %s %s", stored, cols)
	}
}

func fmtSprint(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func urlQuery(s string) string {
	return stringsReplace(s)
}

func stringsReplace(s string) string {
	// small query escape for the two Chinese phrases used above
	r := ""
	for _, c := range s {
		if c < 128 && c != ' ' {
			r += string(c)
			continue
		}
		b := []byte(string(c))
		for _, x := range b {
			r += "%" + hexByte(x)
		}
	}
	return r
}

func hexByte(b byte) string {
	const h = "0123456789ABCDEF"
	return string([]byte{h[b>>4], h[b&15]})
}
