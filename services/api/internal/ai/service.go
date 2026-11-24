package ai

import (
	"context"
	"time"
)

type Service struct {
	Cfg      Config
	Provider Provider
	Quota    Quota
	Now      func() time.Time
}

func New(cfg Config, provider Provider, quota Quota) *Service {
	if quota == nil {
		quota = NewMemoryQuota()
	}
	return &Service{Cfg: cfg, Provider: provider, Quota: quota, Now: time.Now}
}

func (s *Service) Status(loggedIn bool) map[string]any {
	reason := "ready"
	show := s.Cfg.Configured()
	if !s.Cfg.Configured() {
		reason = "no_key"
		show = false
	} else if s.Cfg.Fixture && !loggedIn {
		reason = "fixture"
		show = false
	}
	return map[string]any{
		"provider":    s.Cfg.Provider,
		"configured":  s.Cfg.Configured(),
		"showButton":  show,
		"reason":      reason,
		"guestDaily":  s.Cfg.GuestDaily,
		"memberDaily": s.Cfg.MemberDaily,
		"monthlyCap":  s.Cfg.MonthlyCap,
		"fixture":     s.Cfg.Fixture,
	}
}

func (s *Service) Understand(ctx context.Context, sentence, subject string, member bool) (Understood, string, error) {
	if !s.Cfg.Configured() || s.Provider == nil {
		return Understood{}, "no_key", errUnavailable
	}
	if s.Cfg.Fixture && !member {
		return Understood{}, "fixture", errFixture
	}
	limit := s.Cfg.GuestDaily
	if member {
		limit = s.Cfg.MemberDaily
	}
	now := time.Now()
	if s.Now != nil {
		now = s.Now()
	}
	decision, err := s.Quota.Allows(ctx, subject, limit, s.Cfg.MonthlyCap, now)
	if err != nil {
		return Understood{}, "quota", err
	}
	if !decision.OK {
		return Understood{}, decision.Reason, errCap
	}
	out, err := s.Provider.Understand(ctx, UnderstandRequest{Sentence: sentence})
	if err != nil {
		return Understood{}, "provider", err
	}
	if err := s.Quota.Commit(ctx, subject, now); err != nil {
		return Understood{}, "quota", err
	}
	return out, "", nil
}
