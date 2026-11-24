CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES accounts(id),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS entitlements (
  user_id TEXT PRIMARY KEY REFERENCES accounts(id),
  plan_id TEXT NOT NULL,
  quota_bytes BIGINT NOT NULL,
  used_bytes BIGINT NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS account_state (
  user_id TEXT PRIMARY KEY REFERENCES accounts(id),
  next_cursor BIGINT NOT NULL DEFAULT 1,
  min_cursor BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS player_records (
  owner_id TEXT NOT NULL REFERENCES accounts(id),
  game_id TEXT NOT NULL,
  record_type TEXT NOT NULL,
  record_id TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT '',
  entry_id TEXT NOT NULL DEFAULT '',
  revision BIGINT NOT NULL,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  payload_bytes INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, game_id, record_type, record_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS favorites_entry_uidx
  ON player_records (owner_id, game_id, kind, entry_id)
  WHERE record_type = 'favorite' AND deleted = FALSE;

CREATE TABLE IF NOT EXISTS sync_log (
  owner_id TEXT NOT NULL REFERENCES accounts(id),
  cursor_value BIGINT NOT NULL,
  record_type TEXT NOT NULL,
  record_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  revision BIGINT NOT NULL,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  payload JSONB,
  PRIMARY KEY (owner_id, cursor_value)
);

CREATE TABLE IF NOT EXISTS sync_ops (
  owner_id TEXT NOT NULL REFERENCES accounts(id),
  op_id TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  response JSONB NOT NULL,
  PRIMARY KEY (owner_id, op_id)
);

CREATE TABLE IF NOT EXISTS public_builds (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  title TEXT NOT NULL,
  weapon_type TEXT NOT NULL DEFAULT '',
  rarity INTEGER NOT NULL DEFAULT 0,
  snapshot JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  retracted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL,
  platform_id TEXT NOT NULL,
  region TEXT NOT NULL,
  titles JSONB NOT NULL,
  rewards JSONB NOT NULL,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  timezone TEXT NOT NULL,
  status TEXT NOT NULL,
  verified_at TIMESTAMPTZ NOT NULL,
  source_url TEXT NOT NULL DEFAULT '',
  conditions TEXT NOT NULL DEFAULT '',
  sequence INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS articles (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL,
  locale TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  source_url TEXT NOT NULL DEFAULT '',
  original_language TEXT NOT NULL,
  review_status TEXT NOT NULL,
  verified_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS reminder_subs (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  event_id TEXT NOT NULL REFERENCES events(id),
  platform_id TEXT NOT NULL,
  remind_kind TEXT NOT NULL,
  endpoint TEXT NOT NULL DEFAULT '',
  revoke_hash TEXT NOT NULL DEFAULT '',
  UNIQUE (subject, event_id, platform_id, remind_kind)
);

CREATE TABLE IF NOT EXISTS reminder_jobs (
  id TEXT PRIMARY KEY,
  sub_id TEXT NOT NULL REFERENCES reminder_subs(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  fire_at TIMESTAMPTZ,
  status TEXT NOT NULL
);
