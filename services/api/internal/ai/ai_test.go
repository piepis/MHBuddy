package ai

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestDefaultsDoNotHardcodeModel(t *testing.T) {
	t.Setenv("MH_AI_PROVIDER", "")
	t.Setenv("MH_AI_MODEL", "")
	t.Setenv("MH_AI_API_KEY", "")
	t.Setenv("MH_AI_BASE_URL", "")
	cfg := FromEnv()
	if cfg.Provider != "xai" {
		t.Fatalf("provider %s", cfg.Provider)
	}
	if cfg.Model != "" || cfg.APIKey != "" {
		t.Fatal("model or key should come only from the environment")
	}
	if cfg.BaseURL != DefaultBaseURL {
		t.Fatalf("base %s", cfg.BaseURL)
	}
	if DefaultBaseURL != "https://api.x.ai/v1" {
		t.Fatalf("documented prefix changed: %s", DefaultBaseURL)
	}
	if cfg.GuestDaily != 3 || cfg.MemberDaily != 30 {
		t.Fatalf("quota %d %d", cfg.GuestDaily, cfg.MemberDaily)
	}
	if cfg.Configured() {
		t.Fatal("empty key must not be configured")
	}
}

func TestNoKeyFallsBack(t *testing.T) {
	svc := New(Config{Provider: "xai", Fixture: true}, Fake{}, NewMemoryQuota())
	_, reason, err := svc.Understand(context.Background(), "用铁刀打豺龙", "guest:a", false)
	if reason != "no_key" || err == nil {
		t.Fatalf("reason %s err %v", reason, err)
	}
	if svc.Status(false)["showButton"] != false {
		t.Fatal("button should stay hidden")
	}
}

func TestFixtureHidesGuestsButAllowsMember(t *testing.T) {
	cfg := Config{Provider: "fake", Model: "from-env", APIKey: "secret", Fixture: true, GuestDaily: 3, MemberDaily: 30, MonthlyCap: 100}
	q := NewMemoryQuota()
	svc := New(cfg, Fake{}, q)
	if svc.Status(false)["showButton"] != false {
		t.Fatal("guest button")
	}
	if svc.Status(true)["showButton"] != true {
		t.Fatal("member button")
	}
	_, reason, err := svc.Understand(context.Background(), "世界 铁刀 输出", "guest:a", false)
	if reason != "fixture" || err == nil {
		t.Fatalf("guest %s %v", reason, err)
	}
	if q.Daily("guest:a", time.Now()) != 0 {
		t.Fatal("guest was charged")
	}
	out, reason, err := svc.Understand(context.Background(), "世界 铁刀 输出", "user:hunter-a", true)
	if err != nil || reason != "" || out.GameID != "world" || len(out.WeaponNames) != 1 {
		t.Fatalf("member %+v %s %v", out, reason, err)
	}
}

func TestDailyCap(t *testing.T) {
	cfg := Config{Provider: "fake", Model: "m", APIKey: "k", Fixture: false, GuestDaily: 3, MemberDaily: 30, MonthlyCap: 100}
	svc := New(cfg, Fake{}, NewMemoryQuota())
	for i := 0; i < 3; i++ {
		if _, _, err := svc.Understand(context.Background(), "世界 铁刀 输出", "guest:a", false); err != nil {
			t.Fatal(err)
		}
	}
	_, reason, err := svc.Understand(context.Background(), "世界 铁刀 输出", "guest:a", false)
	if reason != "daily_cap" || err == nil {
		t.Fatalf("cap %s %v", reason, err)
	}
}

func TestChatCompletionsIsStateless(t *testing.T) {
	var seen string
	var auth string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = r.URL.Path
		auth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		body := string(raw)
		if strings.Contains(body, `"store"`) {
			t.Errorf("chat completions must not send store: %s", body)
		}
		if !strings.Contains(body, `"model":"picked-by-env"`) {
			t.Errorf("model %s", body)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"choices":[{"message":{"content":"{\"gameId\":\"world\",\"contentProfile\":\"base\",\"weaponNames\":[\"夹具铁刀\"],\"monsterNames\":[],\"styles\":[\"输出\"],\"ownedText\":[],\"excludeNames\":[],\"assumeUnlimitedJewels\":true,\"clarify\":\"\"}"}}]}`)
	}))
	defer srv.Close()
	var logs []string
	client := &ChatCompletions{
		BaseURL: srv.URL + "/v1",
		APIKey:  "super-secret",
		Model:   "picked-by-env",
		HTTP:    srv.Client(),
		logf:    func(s string) { logs = append(logs, s) },
	}
	out, err := client.Understand(context.Background(), UnderstandRequest{Sentence: "秘密原句不要落日志"})
	if err != nil || out.GameID != "world" {
		t.Fatalf("%v %+v", err, out)
	}
	if seen != "/v1/chat/completions" {
		t.Fatalf("path %s", seen)
	}
	if auth != "Bearer super-secret" {
		t.Fatalf("auth")
	}
	joined := strings.Join(logs, " ")
	if strings.Contains(joined, "秘密原句") || strings.Contains(joined, "super-secret") {
		t.Fatalf("logged secret %s", joined)
	}
}
