CREATE TABLE IF NOT EXISTS wechat_identities (
  openid TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES accounts(id),
  unionid TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS wechat_identities_user_idx ON wechat_identities (user_id);
