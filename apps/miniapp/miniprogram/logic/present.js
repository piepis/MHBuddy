'use strict'

const { t } = require('./i18n')
const { textOf, listEntries, findEntry, summaryOf, poisFor, findMap } = require('./catalog')

function filterEvents(events, opts) {
  const options = opts || {}
  const query = (options.q || '').toLowerCase()
  const reward = (options.reward || '').toLowerCase()
  return (events || []).filter(function (event) {
    if (options.gameId && event.gameId !== options.gameId) return false
    if (event.status === 'revoked') return false
    if (query) {
      const title = textOf(event.titles, options.locale || 'zh-Hans').toLowerCase()
      if (title.indexOf(query) < 0) return false
    }
    if (reward) {
      const names = (event.rewards || []).map(function (item) {
        return textOf(item.names, options.locale || 'zh-Hans').toLowerCase()
      }).join('\n')
      if (names.indexOf(reward) < 0) return false
    }
    return true
  })
}

function homeModel(input) {
  const locale = input.locale || 'zh-Hans'
  const events = filterEvents(input.events, { gameId: input.gameId, locale: locale })
  const first = events[0]
  const pack = input.pack
  return {
    theme: input.theme || 'light',
    gameId: input.gameId,
    profile: input.profile || 'base',
    showMap: input.gameId === 'world',
    showProfile: input.gameId === 'world',
    eventEmpty: !first,
    eventId: first ? first.id : '',
    eventTitle: first ? textOf(first.titles, locale) : t(locale, 'noEvent'),
    eventMeta: first ? ((first.conditions || '') + (first.timezone ? ' · ' + first.timezone : '')) : '',
    reward: first && first.rewards && first.rewards[0] ? textOf(first.rewards[0].names, locale) : '',
    packText: pack ? ((pack.manifest && pack.manifest.dataRevision) || 'fixture-1') + ' · ' + t(locale, 'offlineReady') : t(locale, 'notDownloaded'),
    packAction: pack ? t(locale, 'viewUpdate') : t(locale, 'download'),
    banner: input.apiConfigured ? '' : t(locale, 'apiMissing'),
    fixtureNote: t(locale, 'fixtureNote'),
    labels: {
      viewEvent: t(locale, 'viewEvent'),
      openMap: t(locale, 'openMap'),
      world: t(locale, 'world'),
      wilds: t(locale, 'wilds'),
      base: t(locale, 'base'),
      iceborne: t(locale, 'iceborne'),
      search: t(locale, 'searchPlaceholder')
    }
  }
}

function wikiModel(catalog, opts) {
  const options = opts || {}
  const locale = options.locale || 'zh-Hans'
  const rows = listEntries(catalog, options)
  return {
    rows: rows,
    empty: rows.length === 0,
    emptyText: t(locale, 'noEntries'),
    clearText: t(locale, 'clearFilters'),
    kinds: ['', 'weapon', 'armor', 'monster', 'item', 'skill'].map(function (id) {
      return { id: id, label: t(locale, id || 'all'), on: (options.kind || '') === id }
    })
  }
}

function articleModel(catalog, kind, entryId, locale) {
  const entry = findEntry(catalog, kind, entryId)
  if (!entry) return { missing: true }
  const fields = entry.fields || {}
  const weaknesses = fields.weaknesses || []
  const pois = catalog.gameId === 'world' ? poisFor(catalog, kind, entryId) : []
  return {
    missing: false,
    name: textOf(entry.texts, locale),
    summary: summaryOf(entry.texts, locale),
    meta: [t(locale, entry.kind), (entry.profiles || []).join('/'), catalog.gameId].filter(Boolean).join(' · '),
    weaknesses: weaknesses,
    hasMap: pois.length > 0,
    mapId: pois[0] ? pois[0].mapId : '',
    poiId: pois[0] ? pois[0].poiId : '',
    layerId: pois[0] ? pois[0].layerId : '',
    mapLabel: t(locale, 'mapView'),
    fixture: !!entry.fixture
  }
}

function mapModel(catalog, opts) {
  const options = opts || {}
  const locale = options.locale || 'zh-Hans'
  const map = findMap(catalog, options.mapId)
  if (!map) return { missing: true, text: t(locale, 'layerMissing') }
  const layers = map.layers || []
  const layerId = options.layerId || (layers[0] && layers[0].layerId) || ''
  const layerKnown = layers.some(function (layer) { return layer.layerId === layerId })
  const selectedKinds = options.kinds || ['gather', 'rare-gather']
  const markers = []
  const pois = map.pois || []
  for (let i = 0; i < pois.length; i++) {
    const poi = pois[i]
    if (poi.layerId !== layerId) continue
    if (selectedKinds.indexOf(poi.kind) < 0) continue
    markers.push({
      poiId: poi.poiId,
      left: (poi.xNorm * 100) + '%',
      top: (poi.yNorm * 100) + '%',
      on: poi.poiId === options.selectedPoiId,
      kind: poi.kind,
      area: poi.area || '',
      conditions: poi.conditions || '',
      resourceKind: poi.resourceRef && poi.resourceRef.kind,
      resourceId: poi.resourceRef && poi.resourceRef.entryId
    })
  }
  const selected = null
  let current = null
  for (let i = 0; i < markers.length; i++) if (markers[i].on) current = markers[i]
  return {
    missing: false,
    mapId: map.mapId,
    name: textOf(map.texts, locale),
    layerId: layerId,
    layerKnown: layerKnown,
    layerMissingText: layerKnown ? '' : t(locale, 'layerMissing'),
    layers: layers.map(function (layer) {
      return { id: layer.layerId, name: textOf(layer.texts, locale), on: layer.layerId === layerId }
    }),
    markers: markers,
    selected: current || selected
  }
}

function buildDetail(record, locale) {
  const lang = locale || 'zh-Hans'
  if (!record) return { missing: true, title: t(lang, 'noPublic'), lines: [] }
  if (record.retracted || record.status === 'retracted') {
    return { retracted: true, title: t(lang, 'retracted'), lines: [] }
  }
  const snap = record.snapshot || {}
  const lines = []
  if (snap.weapon && snap.weapon.entryId) lines.push({ slot: 'weapon', entryId: snap.weapon.entryId })
  const armor = snap.armor || []
  for (let i = 0; i < armor.length; i++) lines.push({ slot: armor[i].slot, entryId: armor[i].entryId })
  const decorations = snap.decorations || []
  for (let i = 0; i < decorations.length; i++) {
    lines.push({ slot: 'decoration ' + decorations[i].slotIndex, entryId: decorations[i].entryId })
  }
  return {
    retracted: false,
    missing: false,
    title: record.title || snap.title || '',
    lines: lines,
    tags: snap.tags || [],
    copyLabel: t(lang, 'copyBuild')
  }
}

function accountModel(input) {
  const locale = input.locale || 'zh-Hans'
  const session = input.session
  const statusKey = { local: 'localOnly', syncing: 'syncing', synced: 'synced', pending: 'pending' }[input.syncStatus] || 'localOnly'
  let banner = ''
  if (input.loginCode === 'WECHAT_NOT_CONFIGURED') banner = t(locale, 'wechatBlocked')
  else if (input.loginCode === 'API_BASE_MISSING' || input.loginCode === 'HTTPS_REQUIRED') banner = t(locale, 'apiMissing')
  else if (input.loginCode) banner = input.loginCode
  return {
    theme: input.theme || 'light',
    guest: !session,
    name: session ? (session.displayName || session.userId) : t(locale, 'guest'),
    hint: session ? t(locale, statusKey) : t(locale, 'guestHint'),
    syncStatus: t(locale, statusKey),
    favoriteCount: (input.favorites || []).length,
    entitlement: input.entitlement || null,
    loginLabel: t(locale, 'login'),
    banner: banner
  }
}

module.exports = { filterEvents, homeModel, wikiModel, articleModel, mapModel, buildDetail, accountModel }
