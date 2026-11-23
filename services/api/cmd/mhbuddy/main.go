package main

import (
	"context"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"mhbuddy/services/api/internal/api"
)

func main() {
	root := repoRoot()
	content := getenv("CONTENT_DIR", filepath.Join(root, "content", "fixtures"))
	if len(os.Args) > 1 && os.Args[1] == "pack" {
		dart := filepath.Join(root, "packages", "catalog", "lib", "src", "fixture_public_key.dart")
		if err := api.SignFixtures(content, dart); err != nil {
			log.Fatal(err)
		}
		log.Printf("signed fixtures in %s", content)
		return
	}
	dsn := getenv("DATABASE_URL", "postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable")
	ctx := context.Background()
	admin := adminDSN(dsn)
	name := dbName(dsn)
	if err := api.EnsureDatabase(ctx, admin, name); err != nil {
		log.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	mig, err := os.ReadFile(filepath.Join(root, "services", "api", "migrations", "001_player_records.sql"))
	if err != nil {
		log.Fatal(err)
	}
	if err := api.Migrate(ctx, pool, string(mig)); err != nil {
		log.Fatal(err)
	}
	if err := api.Seed(ctx, pool, content); err != nil {
		log.Fatal(err)
	}
	dev := os.Getenv("MH_DEV_AUTH") == "1"
	web := getenv("WEB_ROOT", filepath.Join(root, "apps", "web", "build", "web"))
	srv := api.New(pool, dev, content, web)
	port := getenv("PORT", "8080")
	ln, err := net.Listen("tcp", "0.0.0.0:"+port)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("MH伙伴助手 listening on http://127.0.0.1:%s/  devAuth=%v", port, dev)
	server := &http.Server{Handler: srv, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(server.Serve(ln))
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func repoRoot() string {
	dir, _ := os.Getwd()
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "docs", "GROK_BUILD_SPEC.md")); err == nil {
			return dir
		}
		dir = filepath.Dir(dir)
	}
	return "."
}

func adminDSN(dsn string) string {
	u, err := url.Parse(dsn)
	if err != nil {
		return dsn
	}
	u.Path = "/postgres"
	return u.String()
}

func dbName(dsn string) string {
	u, err := url.Parse(dsn)
	if err != nil {
		return "mhbuddy"
	}
	name := stringsTrim(u.Path)
	if name == "" {
		return "mhbuddy"
	}
	return name
}

func stringsTrim(p string) string {
	for len(p) > 0 && p[0] == '/' {
		p = p[1:]
	}
	return p
}
