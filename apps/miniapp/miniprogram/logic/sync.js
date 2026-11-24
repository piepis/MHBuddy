'use strict'

const { resolveRequest } = require('./api')

function favoriteId(gameId, kind, entryId) {
  return 'fav-' + gameId + '-' + kind + '-' + entryId
}

function upsertFavorite(state, entry, opId) {
  const favorites = (state.favorites || []).slice()
  const idx = favorites.findIndex(function (row) {
    return row.gameId === entry.gameId && row.kind === entry.kind && row.entryId === entry.entryId
  })
  const row = { gameId: entry.gameId, kind: entry.kind, entryId: entry.entryId, title: entry.title, revision: 0 }
  if (idx >= 0) favorites[idx] = row
  else favorites.push(row)
  const op = {
    opId: opId,
    recordType: 'favorite',
    recordId: favoriteId(entry.gameId, entry.kind, entry.entryId),
    gameId: entry.gameId,
    kind: entry.kind,
    entryId: entry.entryId,
    baseRevision: 0,
    action: 'upsert',
    payload: { title: entry.title }
  }
  return {
    favorites: favorites,
    outbox: (state.outbox || []).concat([op]),
    syncStatus: state.token ? 'pending' : 'local'
  }
}

function applySnapshot(records) {
  const favorites = []
  const list = records || []
  for (let i = 0; i < list.length; i++) {
    const rec = list[i]
    if (rec.recordType !== 'favorite' || rec.deleted) continue
    const payload = rec.payload || {}
    favorites.push({
      gameId: rec.gameId,
      kind: rec.kind,
      entryId: rec.entryId,
      title: payload.title || rec.entryId,
      revision: rec.revision || 0
    })
  }
  return favorites
}

async function pushAndSnapshot(deps) {
  const token = deps.token
  if (!token) return { ok: false, code: 'UNAUTHORIZED', syncStatus: 'local', outbox: deps.outbox || [] }
  const gate = resolveRequest(deps.config, '/v1/sync/push')
  if (!gate.ok) return { ok: false, code: gate.code, syncStatus: 'local', outbox: deps.outbox || [] }
  let remaining = (deps.outbox || []).slice()
  let pending = false
  if (remaining.length) {
    const res = await deps.request({
      url: gate.url,
      method: 'POST',
      data: { ops: remaining.slice(0, 50) },
      header: { Authorization: 'Bearer ' + token, 'content-type': 'application/json' }
    })
    if (!res || res.statusCode === 401) return { ok: false, code: 'UNAUTHORIZED', syncStatus: 'local', outbox: remaining }
    if (res.statusCode !== 200) return { ok: false, code: 'SYNC_FAILED', syncStatus: 'pending', outbox: remaining }
    const results = (res.data && res.data.results) || []
    const done = {}
    for (let i = 0; i < results.length && i < remaining.length; i++) {
      if (results[i].status === 'applied') done[remaining[i].opId] = true
      else pending = true
    }
    remaining = remaining.filter(function (op) { return !done[op.opId] })
  }
  const snapGate = resolveRequest(deps.config, '/v1/sync/snapshot')
  const snap = await deps.request({
    url: snapGate.url,
    method: 'GET',
    header: { Authorization: 'Bearer ' + token }
  })
  if (!snap || snap.statusCode !== 200) {
    return { ok: false, code: 'SYNC_FAILED', syncStatus: 'pending', outbox: remaining }
  }
  return {
    ok: true,
    syncStatus: pending || remaining.length ? 'pending' : 'synced',
    outbox: remaining,
    favorites: applySnapshot(snap.data && snap.data.records),
    watermark: snap.data && snap.data.watermark
  }
}

async function loadEntitlement(deps) {
  const gate = resolveRequest(deps.config, '/v1/me/entitlement')
  if (!gate.ok) return { ok: false, code: gate.code }
  const res = await deps.request({
    url: gate.url,
    method: 'GET',
    header: { Authorization: 'Bearer ' + deps.token }
  })
  if (!res || res.statusCode === 401) return { ok: false, code: 'UNAUTHORIZED' }
  if (res.statusCode !== 200) return { ok: false, code: 'ENTITLEMENT_FAILED' }
  return { ok: true, planId: res.data.planId, quotaBytes: res.data.quotaBytes, usedBytes: res.data.usedBytes }
}

module.exports = { favoriteId, upsertFavorite, applySnapshot, pushAndSnapshot, loadEntitlement }
