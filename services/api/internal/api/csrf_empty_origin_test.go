package api

import (
	"bytes"
	"net/http"
	"testing"
)

func TestCsrfRejectsEmptyOrigin(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	body := bytes.NewReader([]byte(`{"provider":"dev","userId":"empty-origin","displayName":"empty-origin"}`))
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/v1/auth/session", body)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("empty origin %d", res.StatusCode)
	}
	got := readJSON(t, res)
	if got["code"] != "CSRF" {
		t.Fatalf("code %#v", got["code"])
	}
}

func TestPersonalBuildRoundTripPostgres(t *testing.T) {
	srv := testServer(t)
	defer srv.Close()
	cookie := login(t, srv, "hunter-a")
	payload := map[string]any{
		"title":        "夹具配装",
		"fixture":      true,
		"dataRevision": "fixture-1",
		"tags":         []any{"夹具"},
		"weapon":       map[string]any{"entryId": "fixture-iron-sword", "instanceId": "weapon-fixture-iron-sword"},
		"armor":        []any{map[string]any{"slot": "head", "entryId": nil}, map[string]any{"slot": "chest", "entryId": "fixture-fixed-mail"}, map[string]any{"slot": "arms"}, map[string]any{"slot": "waist"}, map[string]any{"slot": "legs"}},
		"decorations":  []any{map[string]any{"part": "chest", "slotIndex": 0, "entryId": "fixture-attack-jewel"}},
	}
	res := do(t, srv, http.MethodPost, "/v1/sync/push", map[string]any{
		"ops": []any{map[string]any{
			"opId": "op-full-1", "recordType": "build", "recordId": "local-1", "gameId": "world",
			"kind": "", "entryId": "", "baseRevision": 0, "action": "upsert", "payload": payload,
		}},
	}, cookie)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("push %d", res.StatusCode)
	}
	pushed := readJSON(t, res)
	results, _ := pushed["results"].([]any)
	if len(results) != 1 || results[0].(map[string]any)["status"] != "applied" {
		t.Fatalf("push result %#v", pushed)
	}
	res = do(t, srv, http.MethodGet, "/v1/sync/snapshot", nil, cookie)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("snapshot %d", res.StatusCode)
	}
	snap := readJSON(t, res)
	records, _ := snap["records"].([]any)
	var found map[string]any
	for _, raw := range records {
		row := raw.(map[string]any)
		if row["recordId"] == "local-1" {
			found = row
		}
	}
	if found == nil {
		t.Fatal("missing build")
	}
	body, _ := found["payload"].(map[string]any)
	weapon, _ := body["weapon"].(map[string]any)
	if weapon["entryId"] != "fixture-iron-sword" {
		t.Fatalf("weapon %#v", body["weapon"])
	}
	armor, _ := body["armor"].([]any)
	if len(armor) != 5 {
		t.Fatalf("armor %#v", body["armor"])
	}
	jewels, _ := body["decorations"].([]any)
	if len(jewels) != 1 || jewels[0].(map[string]any)["entryId"] != "fixture-attack-jewel" {
		t.Fatalf("jewels %#v", body["decorations"])
	}
	other := login(t, srv, "hunter-b")
	res = do(t, srv, http.MethodGet, "/v1/sync/snapshot", nil, other)
	otherSnap := readJSON(t, res)
	records, _ = otherSnap["records"].([]any)
	for _, raw := range records {
		if raw.(map[string]any)["recordId"] == "local-1" {
			t.Fatal("other account can read the build")
		}
	}
}
