package contract

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/santhosh-tekuri/jsonschema/v5"
)

func root(t *testing.T) string {
	t.Helper()
	dir, _ := os.Getwd()
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "docs", "GROK_BUILD_SPEC.md")); err == nil {
			return dir
		}
		dir = filepath.Dir(dir)
	}
	t.Fatal("root")
	return ""
}

func TestBuildExamples(t *testing.T) {
	r := root(t)
	schemaPath := filepath.Join(r, "contracts", "schemas", "build.schema.json")
	sch, err := jsonschema.Compile(schemaPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"wilds-build-v1.fixture.json", "wilds-build-equipped.fixture.json"} {
		raw, err := os.ReadFile(filepath.Join(r, "contracts", "examples", name))
		if err != nil {
			t.Fatal(err)
		}
		var v any
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatal(err)
		}
		if err := sch.Validate(v); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	spec, err := os.ReadFile(filepath.Join(r, "contracts", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"/v1/packs/latest", "/v1/events", "/v1/public-builds", "/v1/auth/session", "/v1/sync/push", "/v1/sync/pull", "/v1/me/entitlement"} {
		if !strings.Contains(string(spec), p) {
			t.Fatalf("openapi missing %s", p)
		}
	}
}
