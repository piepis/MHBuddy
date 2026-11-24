-- Account preferences, anonymous analytics, and structured AI usage.
-- Raw hunter sentences and plaintext IP addresses are not columns.

CREATE TABLE IF NOT EXISTS account_preferences (
  user_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  locale TEXT NOT NULL DEFAULT 'zh-Hans',
  theme TEXT NOT NULL DEFAULT 'light',
  content_profile TEXT NOT NULL DEFAULT 'base',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS visitors (
  id TEXT PRIMARY KEY,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  linked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS analytics_events (
  id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  visitor_id TEXT NOT NULL REFERENCES visitors(id) ON DELETE CASCADE,
  user_id TEXT,
  event_type TEXT NOT NULL,
  game_id TEXT NOT NULL DEFAULT '',
  content_profile TEXT NOT NULL DEFAULT '',
  path TEXT NOT NULL DEFAULT '',
  query_norm TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT '',
  entry_id TEXT NOT NULL DEFAULT '',
  weapon_id TEXT NOT NULL DEFAULT '',
  monster_id TEXT NOT NULL DEFAULT '',
  styles JSONB NOT NULL DEFAULT '[]'::jsonb,
  public_id TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS analytics_events_time_idx ON analytics_events (occurred_at);
CREATE INDEX IF NOT EXISTS analytics_events_type_idx ON analytics_events (event_type, occurred_at);

CREATE TABLE IF NOT EXISTS ai_usage_log (
  id BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  subject TEXT NOT NULL,
  user_id TEXT,
  game_id TEXT NOT NULL DEFAULT '',
  content_profile TEXT NOT NULL DEFAULT '',
  weapon_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  monster_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  styles JSONB NOT NULL DEFAULT '[]'::jsonb,
  entry_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  inventory_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  excluded_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  assume_unlimited BOOLEAN NOT NULL DEFAULT FALSE,
  counted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS ai_usage_log_time_idx ON ai_usage_log (occurred_at);
