package api

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
)

func loadSeed(keysDir string) (ed25519.PrivateKey, ed25519.PublicKey, error) {
	if err := os.MkdirAll(keysDir, 0o755); err != nil {
		return nil, nil, err
	}
	seedPath := filepath.Join(keysDir, "fixture-ed25519.seed")
	raw, err := os.ReadFile(seedPath)
	if err != nil {
		_, priv, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return nil, nil, err
		}
		seed := priv.Seed()
		if err := os.WriteFile(seedPath, []byte(hex.EncodeToString(seed)+"\n"), 0o644); err != nil {
			return nil, nil, err
		}
		raw = []byte(hex.EncodeToString(seed))
	}
	seed, err := hex.DecodeString(string(trimSpace(raw)))
	if err != nil {
		return nil, nil, err
	}
	priv := ed25519.NewKeyFromSeed(seed)
	pub := priv.Public().(ed25519.PublicKey)
	pubPath := filepath.Join(keysDir, "fixture-ed25519.pub")
	if err := os.WriteFile(pubPath, []byte(hex.EncodeToString(pub)+"\n"), 0o644); err != nil {
		return nil, nil, err
	}
	return priv, pub, nil
}

func trimSpace(b []byte) []byte {
	out := make([]byte, 0, len(b))
	for _, c := range b {
		if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
			out = append(out, c)
		}
	}
	return out
}

type Manifest struct {
	GameID          string   `json:"gameId"`
	ContentProfiles []string `json:"contentProfiles"`
	PlatformID      string   `json:"platformId"`
	PatchID         string   `json:"patchId"`
	DataRevision    string   `json:"dataRevision"`
	RevisionNumber  int      `json:"revisionNumber"`
	SchemaVersion   int      `json:"schemaVersion"`
	RulesetVersion  string   `json:"rulesetVersion"`
	MinClient       string   `json:"minClient"`
	Size            int      `json:"size"`
	SHA256          string   `json:"sha256"`
	Signature       string   `json:"signature"`
	URL             string   `json:"url"`
	Fixture         bool     `json:"fixture"`
	Changelog       string   `json:"changelog"`
}

func SignFixtures(contentDir, dartKeyPath string) error {
	priv, pub, err := loadSeed(filepath.Join(contentDir, "keys"))
	if err != nil {
		return err
	}
	if dartKeyPath != "" {
		src := "/// Fixture verify key. Not a production trust anchor.\nconst String fixturePublicKeyHex = '" + hex.EncodeToString(pub) + "';\n"
		if err := os.MkdirAll(filepath.Dir(dartKeyPath), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dartKeyPath, []byte(src), 0o644); err != nil {
			return err
		}
	}
	manDir := filepath.Join(contentDir, "manifests")
	if err := os.MkdirAll(manDir, 0o755); err != nil {
		return err
	}
	files := []struct {
		name  string
		url   string
		game  string
		profs []string
	}{
		{"catalog-world.json", "/fixtures/catalog-world.json", "world", []string{"base", "iceborne"}},
		{"catalog-wilds.json", "/fixtures/catalog-wilds.json", "wilds", []string{"base"}},
	}
	for _, f := range files {
		body, err := os.ReadFile(filepath.Join(contentDir, f.name))
		if err != nil {
			return err
		}
		sum := sha256.Sum256(body)
		hexSum := hex.EncodeToString(sum[:])
		sig := ed25519.Sign(priv, []byte(hexSum))
		m := Manifest{
			GameID: f.game, ContentProfiles: f.profs, PlatformID: "pc", PatchID: "fixture-p1",
			DataRevision: "fixture-1", RevisionNumber: 1, SchemaVersion: 1, RulesetVersion: "fixture-r1",
			MinClient: "0.1.0", Size: len(body), SHA256: hexSum, Signature: base64.StdEncoding.EncodeToString(sig),
			URL: f.url, Fixture: true, Changelog: "合成夹具，不是实数资料",
		}
		out, err := json.MarshalIndent(m, "", "  ")
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(manDir, f.game+".json"), append(out, '\n'), 0o644); err != nil {
			return err
		}
	}
	return nil
}

func VerifyFixture(pub ed25519.PublicKey, body []byte, signatureB64 string) bool {
	sum := sha256.Sum256(body)
	sig, err := base64.StdEncoding.DecodeString(signatureB64)
	if err != nil {
		return false
	}
	return ed25519.Verify(pub, []byte(hex.EncodeToString(sum[:])), sig)
}
