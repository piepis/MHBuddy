'use strict'

function memoryStore(initial) {
  const data = Object.assign({}, initial || {})
  return {
    get: function (key) { return data[key] },
    set: function (key, value) { data[key] = value },
    dump: function () { return data }
  }
}

function savePack(store, gameId, record) {
  const key = 'pack:' + gameId
  const prev = store.get(key)
  const nextRev = record && record.revisionNumber
  if (prev && typeof prev.revisionNumber === 'number' && typeof nextRev === 'number' && nextRev < prev.revisionNumber) {
    return { ok: false, code: 'STALE_REVISION' }
  }
  const saved = {
    gameId: gameId,
    revisionNumber: record.revisionNumber,
    manifest: record.manifest,
    catalog: record.catalog,
    savedAt: record.savedAt,
    hash: record.hash,
    fixture: !!(record.manifest && record.manifest.fixture)
  }
  store.set(key, saved)
  return { ok: true, pack: saved }
}

function loadPack(store, gameId) {
  return store.get('pack:' + gameId) || null
}

function chooseCatalog(bundled, cached) {
  if (!cached || !cached.catalog) return { catalog: bundled, source: 'bundle' }
  const bundledRev = (bundled && bundled.revisionNumber) || 0
  const cachedRev = cached.revisionNumber || 0
  if (cachedRev >= bundledRev) return { catalog: cached.catalog, source: 'cache' }
  return { catalog: bundled, source: 'bundle' }
}

module.exports = { memoryStore, savePack, loadPack, chooseCatalog }
