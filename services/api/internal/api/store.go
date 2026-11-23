package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	Pool *pgxpool.Pool
}

type Op struct {
	OpID         string          `json:"opId"`
	RecordType   string          `json:"recordType"`
	RecordID     string          `json:"recordId"`
	GameID       string          `json:"gameId"`
	Kind         string          `json:"kind"`
	EntryID      string          `json:"entryId"`
	BaseRevision int64           `json:"baseRevision"`
	Action       string          `json:"action"`
	Payload      json.RawMessage `json:"payload"`
}

type Result struct {
	OpID     string         `json:"opId"`
	Status   string         `json:"status"`
	Revision int64          `json:"revision,omitempty"`
	Cursor   int64          `json:"cursor,omitempty"`
	Code     string         `json:"code,omitempty"`
	Details  map[string]any `json:"details,omitempty"`
}

func opHash(op Op) string {
	b, _ := json.Marshal(op)
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func (s *Store) Apply(ctx context.Context, user string, op Op) (Result, error) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return Result{}, err
	}
	defer tx.Rollback(ctx)

	hash := opHash(op)
	var oldHash string
	var raw []byte
	err = tx.QueryRow(ctx, `SELECT payload_hash, response FROM sync_ops WHERE owner_id=$1 AND op_id=$2`, user, op.OpID).Scan(&oldHash, &raw)
	if err == nil {
		if oldHash == hash {
			var stored Result
			if jerr := json.Unmarshal(raw, &stored); jerr != nil {
				return Result{}, jerr
			}
			return stored, nil
		}
		return Result{OpID: op.OpID, Status: "rejected", Code: "IDEMPOTENCY_CONFLICT"}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Result{}, err
	}

	if op.GameID != "world" && op.GameID != "wilds" {
		return reject(op, "VALIDATION"), nil
	}
	if op.Action != "upsert" && op.Action != "delete" {
		return reject(op, "VALIDATION"), nil
	}
	if op.RecordType != "favorite" && op.RecordType != "inventory" && op.RecordType != "build" {
		return reject(op, "VALIDATION"), nil
	}
	if len(op.Payload) == 0 {
		op.Payload = []byte(`{}`)
	}
	if !json.Valid(op.Payload) {
		return reject(op, "VALIDATION"), nil
	}

	if op.RecordType == "favorite" && op.Action == "upsert" {
		var existingID string
		var existingRev int64
		err = tx.QueryRow(ctx, `
			SELECT record_id, revision FROM player_records
			WHERE owner_id=$1 AND game_id=$2 AND record_type='favorite' AND kind=$3 AND entry_id=$4 AND deleted=FALSE
		`, user, op.GameID, op.Kind, op.EntryID).Scan(&existingID, &existingRev)
		if err == nil && existingID != op.RecordID {
			res := Result{OpID: op.OpID, Status: "applied", Revision: existingRev, Details: map[string]any{"deduped": true, "recordId": existingID}}
			if err = finishOp(ctx, tx, user, op, hash, res); err != nil {
				return Result{}, err
			}
			return res, tx.Commit(ctx)
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return Result{}, err
		}
	}

	var curRev int64
	var curDeleted bool
	var curPayload []byte
	var curBytes int
	var found bool
	err = tx.QueryRow(ctx, `
		SELECT revision, deleted, payload, payload_bytes FROM player_records
		WHERE owner_id=$1 AND game_id=$2 AND record_type=$3 AND record_id=$4
	`, user, op.GameID, op.RecordType, op.RecordID).Scan(&curRev, &curDeleted, &curPayload, &curBytes)
	if err == nil {
		found = true
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return Result{}, err
	}
	baseHave := int64(0)
	if found && !curDeleted {
		baseHave = curRev
	}
	if op.BaseRevision != baseHave {
		res := Result{OpID: op.OpID, Status: "conflict", Code: "REVISION_CONFLICT", Details: map[string]any{
			"serverRevision": baseHave,
			"deleted":        found && curDeleted,
			"payload":        json.RawMessage(curPayload),
		}}
		return res, nil
	}

	if op.RecordType == "inventory" && op.Action == "upsert" {
		var body struct {
			Quantity int `json:"quantity"`
		}
		if err := json.Unmarshal(op.Payload, &body); err != nil || body.Quantity < 0 {
			return reject(op, "VALIDATION"), nil
		}
	}

	newBytes := 0
	deleted := op.Action == "delete"
	if !deleted {
		newBytes = len(op.Payload)
	}
	oldBytes := 0
	if found && !curDeleted {
		oldBytes = curBytes
	}
	delta := newBytes - oldBytes

	var quota, used int64
	err = tx.QueryRow(ctx, `SELECT quota_bytes, used_bytes FROM entitlements WHERE user_id=$1 FOR UPDATE`, user).Scan(&quota, &used)
	if err != nil {
		return Result{}, err
	}
	if delta > 0 && used+int64(delta) > quota {
		return Result{OpID: op.OpID, Status: "rejected", Code: "QUOTA_EXCEEDED", Details: map[string]any{"quotaBytes": quota, "usedBytes": used}}, nil
	}

	newRev := int64(1)
	if found {
		newRev = curRev + 1
	}
	payload := op.Payload
	if deleted {
		if len(curPayload) > 0 {
			payload = curPayload
		}
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO player_records (owner_id, game_id, record_type, record_id, kind, entry_id, revision, deleted, payload, payload_bytes, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, now())
		ON CONFLICT (owner_id, game_id, record_type, record_id) DO UPDATE SET
		  kind=EXCLUDED.kind, entry_id=EXCLUDED.entry_id, revision=EXCLUDED.revision,
		  deleted=EXCLUDED.deleted, payload=EXCLUDED.payload, payload_bytes=EXCLUDED.payload_bytes, updated_at=now()
	`, user, op.GameID, op.RecordType, op.RecordID, op.Kind, op.EntryID, newRev, deleted, payload, newBytes)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return reject(op, "DUPLICATE_FAVORITE"), nil
		}
		return Result{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE entitlements SET used_bytes = used_bytes + $2 WHERE user_id=$1`, user, delta); err != nil {
		return Result{}, err
	}
	var cursor int64
	if err = tx.QueryRow(ctx, `UPDATE account_state SET next_cursor = next_cursor + 1 WHERE user_id=$1 RETURNING next_cursor - 1`, user).Scan(&cursor); err != nil {
		return Result{}, err
	}
	if _, err = tx.Exec(ctx, `
		INSERT INTO sync_log (owner_id, cursor_value, record_type, record_id, game_id, revision, deleted, payload)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
	`, user, cursor, op.RecordType, op.RecordID, op.GameID, newRev, deleted, payload); err != nil {
		return Result{}, err
	}
	res := Result{OpID: op.OpID, Status: "applied", Revision: newRev, Cursor: cursor}
	if err = finishOp(ctx, tx, user, op, hash, res); err != nil {
		return Result{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Result{}, err
	}
	return res, nil
}

func reject(op Op, code string) Result {
	return Result{OpID: op.OpID, Status: "rejected", Code: code}
}

func finishOp(ctx context.Context, tx pgx.Tx, user string, op Op, hash string, res Result) error {
	raw, err := json.Marshal(res)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO sync_ops (owner_id, op_id, payload_hash, response) VALUES ($1,$2,$3,$4)`, user, op.OpID, hash, raw)
	return err
}

type Change struct {
	Cursor     int64           `json:"cursor"`
	RecordType string          `json:"recordType"`
	RecordID   string          `json:"recordId"`
	GameID     string          `json:"gameId"`
	Revision   int64           `json:"revision"`
	Deleted    bool            `json:"deleted"`
	Payload    json.RawMessage `json:"payload,omitempty"`
}

func (s *Store) Pull(ctx context.Context, user string, since int64, limit int) ([]Change, int64, error) {
	var minC int64
	if err := s.Pool.QueryRow(ctx, `SELECT min_cursor FROM account_state WHERE user_id=$1`, user).Scan(&minC); err != nil {
		return nil, 0, err
	}
	if since < minC {
		return nil, 0, errCursorExpired
	}
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT cursor_value, record_type, record_id, game_id, revision, deleted, payload
		FROM sync_log WHERE owner_id=$1 AND cursor_value > $2 ORDER BY cursor_value LIMIT $3
	`, user, since, limit)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var out []Change
	next := since
	for rows.Next() {
		var c Change
		if err := rows.Scan(&c.Cursor, &c.RecordType, &c.RecordID, &c.GameID, &c.Revision, &c.Deleted, &c.Payload); err != nil {
			return nil, 0, err
		}
		next = c.Cursor
		out = append(out, c)
	}
	if out == nil {
		out = []Change{}
	}
	return out, next, rows.Err()
}

var errCursorExpired = fmt.Errorf("CURSOR_EXPIRED")

func (s *Store) Snapshot(ctx context.Context, user string) (map[string]any, error) {
	var watermark int64
	if err := s.Pool.QueryRow(ctx, `SELECT next_cursor - 1 FROM account_state WHERE user_id=$1`, user).Scan(&watermark); err != nil {
		return nil, err
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT game_id, record_type, record_id, kind, entry_id, revision, payload
		FROM player_records WHERE owner_id=$1 AND deleted=FALSE ORDER BY game_id, record_type, record_id
	`, user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var records []map[string]any
	for rows.Next() {
		var game, typ, id, kind, entry string
		var rev int64
		var payload []byte
		if err := rows.Scan(&game, &typ, &id, &kind, &entry, &rev, &payload); err != nil {
			return nil, err
		}
		records = append(records, map[string]any{
			"gameId": game, "recordType": typ, "recordId": id, "kind": kind, "entryId": entry, "revision": rev, "payload": json.RawMessage(payload),
		})
	}
	if records == nil {
		records = []map[string]any{}
	}
	return map[string]any{"watermark": watermark, "records": records}, rows.Err()
}

func (s *Store) SetEntitlement(ctx context.Context, user, plan string, quota int64) error {
	_, err := s.Pool.Exec(ctx, `UPDATE entitlements SET plan_id=$2, quota_bytes=$3 WHERE user_id=$1`, user, plan, quota)
	return err
}

func (s *Store) Compact(ctx context.Context, user string) error {
	_, err := s.Pool.Exec(ctx, `UPDATE account_state SET min_cursor = next_cursor - 1 WHERE user_id=$1`, user)
	return err
}

func (s *Store) Used(ctx context.Context, user string) (int64, int64, error) {
	var q, u int64
	err := s.Pool.QueryRow(ctx, `SELECT quota_bytes, used_bytes FROM entitlements WHERE user_id=$1`, user).Scan(&q, &u)
	return q, u, err
}
