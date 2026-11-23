package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Understood is the only structure a model may return. It must not contain
// attack values, skill levels, or catalog ids.
type Understood struct {
	GameID                string   `json:"gameId"`
	ContentProfile        string   `json:"contentProfile"`
	WeaponNames           []string `json:"weaponNames"`
	MonsterNames          []string `json:"monsterNames"`
	Styles                []string `json:"styles"`
	OwnedText             []string `json:"ownedText"`
	ExcludeNames          []string `json:"excludeNames"`
	AssumeUnlimitedJewels bool     `json:"assumeUnlimitedJewels"`
	Clarify               string   `json:"clarify"`
}

type UnderstandRequest struct {
	Sentence string
	GameHint string
}

type Provider interface {
	Understand(ctx context.Context, req UnderstandRequest) (Understood, error)
}

// ChatCompletions calls a stateless OpenAI-compatible chat completions endpoint.
// It does not use the Responses API, so there is no store flag to turn on.
type ChatCompletions struct {
	BaseURL string
	APIKey  string
	Model   string
	HTTP    *http.Client
	// logf receives status text only. Callers must not pass the sentence or key.
	logf func(string)
}

func (c *ChatCompletions) Understand(ctx context.Context, req UnderstandRequest) (Understood, error) {
	if strings.TrimSpace(c.Model) == "" || strings.TrimSpace(c.APIKey) == "" {
		return Understood{}, fmt.Errorf("ai not configured")
	}
	payload := map[string]any{
		"model":       c.Model,
		"temperature": 0,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": req.Sentence},
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return Understood{}, err
	}
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 20 * time.Second}
	}
	endpoint := strings.TrimRight(c.BaseURL, "/") + "/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return Understood{}, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
	res, err := httpClient.Do(httpReq)
	if err != nil {
		c.note("chat completions transport error")
		return Understood{}, err
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return Understood{}, err
	}
	if res.StatusCode != http.StatusOK {
		c.note(fmt.Sprintf("chat completions status %d", res.StatusCode))
		return Understood{}, fmt.Errorf("status %d", res.StatusCode)
	}
	var envelope struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &envelope); err != nil || len(envelope.Choices) == 0 {
		c.note("chat completions unreadable")
		return Understood{}, fmt.Errorf("unreadable completion")
	}
	return parseUnderstood(envelope.Choices[0].Message.Content)
}

func (c *ChatCompletions) note(msg string) {
	if c.logf != nil {
		c.logf(msg)
	}
}

const systemPrompt = `You convert one hunter sentence into JSON only. Keys: gameId (world, wilds, or empty), contentProfile (base, iceborne, or empty), weaponNames, monsterNames, styles, ownedText, excludeNames, assumeUnlimitedJewels, clarify. Use names the hunter said. Do not invent attack, affinity, skill levels, equipment ids, or drop rates. If the sentence is ambiguous, set clarify to a short question and leave the uncertain lists empty. assumeUnlimitedJewels is true only when the hunter did not name jewels they own.`

func parseUnderstood(content string) (Understood, error) {
	text := strings.TrimSpace(content)
	text = strings.TrimPrefix(text, "```json")
	text = strings.TrimPrefix(text, "```")
	text = strings.TrimSuffix(text, "```")
	text = strings.TrimSpace(text)
	var out Understood
	if err := json.Unmarshal([]byte(text), &out); err != nil {
		return Understood{}, err
	}
	if out.GameID != "" && out.GameID != "world" && out.GameID != "wilds" {
		return Understood{}, fmt.Errorf("game")
	}
	return out, nil
}

// Fake understands a few fixture phrases and never calls a network.
type Fake struct{}

func (Fake) Understand(_ context.Context, req UnderstandRequest) (Understood, error) {
	s := req.Sentence
	out := Understood{AssumeUnlimitedJewels: true, ContentProfile: "base"}
	if strings.Contains(s, "荒野") {
		out.GameID = "wilds"
	} else if strings.Contains(s, "世界") || strings.Contains(s, "冰原") {
		out.GameID = "world"
	}
	if strings.Contains(s, "冰原") {
		out.ContentProfile = "iceborne"
	}
	if strings.Contains(s, "铁刀") {
		out.WeaponNames = []string{"夹具铁刀"}
	}
	if strings.Contains(s, "试作武器") {
		out.WeaponNames = []string{"夹具试作武器W"}
	}
	if strings.Contains(s, "豺龙") {
		out.MonsterNames = []string{"夹具大凶豺龙"}
	}
	if strings.Contains(s, "攻击") || strings.Contains(s, "输出") {
		out.Styles = append(out.Styles, "输出")
	}
	if strings.Contains(s, "会心") {
		out.Styles = append(out.Styles, "会心")
	}
	if strings.Contains(s, "不要") && strings.Contains(s, "素头") {
		out.ExcludeNames = []string{"夹具素头"}
	}
	if strings.Contains(s, "两颗") || strings.Contains(s, "攻击珠") {
		out.OwnedText = []string{"夹具攻击珠 2"}
		out.AssumeUnlimitedJewels = false
	}
	if out.GameID == "" || (len(out.WeaponNames) == 0 && len(out.MonsterNames) == 0 && len(out.Styles) == 0) {
		out.Clarify = "请说明作品、武器或风格"
	}
	return out, nil
}
