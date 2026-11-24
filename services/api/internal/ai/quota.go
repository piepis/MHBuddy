package ai

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Decision struct {
	OK     bool
	Reason string
}

// Quota counts successful understands. It does not store sentences.
type Quota interface {
	Allows(ctx context.Context, subject string, dailyLimit, monthlyLimit int, now time.Time) (Decision, error)
	Commit(ctx context.Context, subject string, now time.Time) error
}

type MemoryQuota struct {
	mu      sync.Mutex
	daily   map[string]int
	monthly map[string]int
}

func NewMemoryQuota() *MemoryQuota {
	return &MemoryQuota{daily: map[string]int{}, monthly: map[string]int{}}
}

func (m *MemoryQuota) Allows(_ context.Context, subject string, dailyLimit, monthlyLimit int, now time.Time) (Decision, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if monthlyLimit >= 0 && m.monthly[now.UTC().Format("2006-01")] >= monthlyLimit {
		return Decision{Reason: "monthly_cap"}, nil
	}
	if dailyLimit >= 0 && m.daily[m.dayKey(subject, now)] >= dailyLimit {
		return Decision{Reason: "daily_cap"}, nil
	}
	return Decision{OK: true}, nil
}

func (m *MemoryQuota) Commit(_ context.Context, subject string, now time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.daily[m.dayKey(subject, now)]++
	m.monthly[now.UTC().Format("2006-01")]++
	return nil
}

func (m *MemoryQuota) dayKey(subject string, now time.Time) string {
	return subject + "|" + now.UTC().Format("2006-01-02")
}

func (m *MemoryQuota) Daily(subject string, now time.Time) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.daily[m.dayKey(subject, now)]
}

type PGQuota struct {
	Pool *pgxpool.Pool
}

func NewPGQuota(pool *pgxpool.Pool) *PGQuota { return &PGQuota{Pool: pool} }

func (p *PGQuota) Allows(ctx context.Context, subject string, dailyLimit, monthlyLimit int, now time.Time) (Decision, error) {
	var monthUsed, dayUsed int
	err := p.Pool.QueryRow(ctx, `SELECT COALESCE((SELECT used FROM ai_monthly WHERE month=$1), 0), COALESCE((SELECT used FROM ai_daily WHERE subject=$2 AND day=$3), 0)`,
		now.UTC().Format("2006-01"), subject, now.UTC()).Scan(&monthUsed, &dayUsed)
	if err != nil {
		return Decision{}, err
	}
	if monthlyLimit >= 0 && monthUsed >= monthlyLimit {
		return Decision{Reason: "monthly_cap"}, nil
	}
	if dailyLimit >= 0 && dayUsed >= dailyLimit {
		return Decision{Reason: "daily_cap"}, nil
	}
	return Decision{OK: true}, nil
}

func (p *PGQuota) Commit(ctx context.Context, subject string, now time.Time) error {
	tx, err := p.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `INSERT INTO ai_monthly (month, used) VALUES ($1, 1) ON CONFLICT (month) DO UPDATE SET used = ai_monthly.used + 1`, now.UTC().Format("2006-01")); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO ai_daily (subject, day, used) VALUES ($1, $2, 1) ON CONFLICT (subject, day) DO UPDATE SET used = ai_daily.used + 1`, subject, now.UTC()); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
