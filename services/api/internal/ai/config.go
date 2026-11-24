package ai

import (
	"os"
	"strconv"
	"strings"
)

// DefaultBaseURL is the OpenAI-compatible prefix from the xAI quickstart
// (https://docs.x.ai/developers/quickstart). The inference host is https://api.x.ai.
// Override with MH_AI_BASE_URL if the documented prefix changes.
const DefaultBaseURL = "https://api.x.ai/v1"

type Config struct {
	Provider    string
	Model       string
	APIKey      string
	BaseURL     string
	GuestDaily  int
	MemberDaily int
	MonthlyCap  int
	Fixture     bool
}

func FromEnv() Config {
	cfg := Config{
		Provider:    getenv("MH_AI_PROVIDER", "xai"),
		Model:       strings.TrimSpace(os.Getenv("MH_AI_MODEL")),
		APIKey:      strings.TrimSpace(os.Getenv("MH_AI_API_KEY")),
		BaseURL:     strings.TrimRight(getenv("MH_AI_BASE_URL", DefaultBaseURL), "/"),
		GuestDaily:  getenvInt("MH_AI_GUEST_DAILY", 3),
		MemberDaily: getenvInt("MH_AI_MEMBER_DAILY", 30),
		MonthlyCap:  getenvInt("MH_AI_MONTHLY_CAP", 100),
		Fixture:     getenv("MH_CONTENT_FIXTURE", "1") != "0",
	}
	if cfg.Provider == "" {
		cfg.Provider = "xai"
	}
	return cfg
}

func (c Config) Configured() bool {
	return c.APIKey != "" && c.Model != "" && c.Provider != "" && c.Provider != "off"
}

func getenv(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func getenvInt(k string, def int) int {
	v := strings.TrimSpace(os.Getenv(k))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	return n
}
