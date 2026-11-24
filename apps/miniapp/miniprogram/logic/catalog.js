'use strict'

const { t } = require('./i18n')

function normalize(value) {
  let text = String(value || '')
  try {
    text = text.normalize('NFKC')
  } catch (err) {}
  return text.toLowerCase().replace(/\s+/g, '')
}

function textOf(texts, locale) {
  if (!texts) return ''
  if (typeof texts === 'string') return texts
  const order = [locale || 'zh-Hans', 'zh-Hans', 'en', 'ja', 'zh-Hant']
  for (let i = 0; i < order.length; i++) {
    const block = texts[order[i]]
    if (!block) continue
    if (typeof block === 'string') return block
    if (block.name) return block.name
  }
  const keys = Object.keys(texts)
  if (!keys.length) return ''
  const first = texts[keys[0]]
  return typeof first === 'string' ? first : (first && first.name) || ''
}

function summaryOf(texts, locale) {
  if (!texts || typeof texts === 'string') return ''
  const order = [locale || 'zh-Hans', 'zh-Hans', 'en', 'ja', 'zh-Hant']
  for (let i = 0; i < order.length; i++) {
    const block = texts[order[i]]
    if (block && block.summary) return block.summary
  }
  return ''
}

function entryVisible(entry, profile) {
  const profiles = entry.profiles || []
  if (!profiles.length) return true
  if (profile === 'iceborne') return profiles.indexOf('base') >= 0 || profiles.indexOf('iceborne') >= 0
  return profiles.indexOf(profile || 'base') >= 0
}

function listEntries(catalog, opts) {
  const options = opts || {}
  const kind = options.kind || ''
  const query = normalize(options.q || '')
  const locale = options.locale || 'zh-Hans'
  const profile = options.profile || 'base'
  const out = []
  const entries = (catalog && catalog.entries) || []
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]
    if (kind && entry.kind !== kind) continue
    if (catalog.gameId === 'world' && !entryVisible(entry, profile)) continue
    const name = textOf(entry.texts, locale) || entry.entryId
    const block = entry.texts && (entry.texts[locale] || entry.texts['zh-Hans'])
    const aliases = (block && block.aliases) || []
    if (query) {
      const hay = [name, entry.entryId].concat(aliases).map(normalize).join('\n')
      if (hay.indexOf(query) < 0) continue
    }
    const profileText = (entry.profiles || []).join('/')
    out.push({
      kind: entry.kind,
      entryId: entry.entryId,
      name: name,
      summary: summaryOf(entry.texts, locale),
      subtitle: t(locale, entry.kind) + (profileText ? ' · ' + profileText : '')
    })
  }
  out.sort(function (a, b) {
    if (a.name === b.name) return a.entryId < b.entryId ? -1 : 1
    return a.name < b.name ? -1 : 1
  })
  return out
}

function findEntry(catalog, kind, entryId) {
  const entries = (catalog && catalog.entries) || []
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].kind === kind && entries[i].entryId === entryId) return entries[i]
  }
  return null
}

function poisFor(catalog, kind, entryId) {
  const hits = []
  const maps = (catalog && catalog.maps) || []
  for (let i = 0; i < maps.length; i++) {
    const map = maps[i]
    const pois = map.pois || []
    for (let j = 0; j < pois.length; j++) {
      const poi = pois[j]
      const ref = poi.resourceRef || {}
      if (ref.kind === kind && ref.entryId === entryId) {
        hits.push({
          mapId: map.mapId,
          mapName: textOf(map.texts, 'zh-Hans'),
          poiId: poi.poiId,
          layerId: poi.layerId,
          xNorm: poi.xNorm,
          yNorm: poi.yNorm,
          area: poi.area,
          kind: poi.kind,
          conditions: poi.conditions
        })
      }
    }
  }
  return hits
}

function findMap(catalog, mapId) {
  const maps = (catalog && catalog.maps) || []
  for (let i = 0; i < maps.length; i++) {
    if (!mapId || maps[i].mapId === mapId) return maps[i]
  }
  return null
}

module.exports = { normalize, textOf, summaryOf, listEntries, findEntry, poisFor, findMap, entryVisible }
