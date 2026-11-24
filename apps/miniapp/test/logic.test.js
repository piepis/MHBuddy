'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const test = require('node:test')
const crypto = require('node:crypto')

const { sha256Hex } = require('../miniprogram/logic/sha256')
const api = require('../miniprogram/logic/api')
const { t, locales, STR } = require('../miniprogram/logic/i18n')
const catalog = require('../miniprogram/logic/catalog')
const present = require('../miniprogram/logic/present')
const auth = require('../miniprogram/logic/auth')
const sync = require('../miniprogram/logic/sync')
const reminders = require('../miniprogram/logic/reminders')
const integrity = require('../miniprogram/logic/integrity')
const cache = require('../miniprogram/logic/cache')
const packs = require('../miniprogram/logic/packs')
const config = require('../miniprogram/config')

const repo = path.resolve(__dirname, '../../..')
const fixtures = path.join(repo, 'content', 'fixtures')
const world = JSON.parse(fs.readFileSync(path.join(fixtures, 'catalog-world.json'), 'utf8'))
const events = JSON.parse(fs.readFileSync(path.join(fixtures, 'events.json'), 'utf8'))
const builds = JSON.parse(fs.readFileSync(path.join(fixtures, 'public-builds.json'), 'utf8'))
const worldManifest = JSON.parse(fs.readFileSync(path.join(fixtures, 'manifests', 'world.json'), 'utf8'))
const worldText = fs.readFileSync(path.join(fixtures, 'catalog-world.json'), 'utf8')
const pub = fs.readFileSync(path.join(fixtures, 'keys', 'fixture-ed25519.pub'), 'utf8').trim()
const nacl = require('../miniprogram/vendor/tweetnacl')

test('sha256 matches node crypto', function () {
  for (const sample of ['', 'abc', worldText]) {
    assert.equal(sha256Hex(sample), crypto.createHash('sha256').update(sample, 'utf8').digest('hex'))
  }
})

test('placeholder config has no real app id or API host', function () {
  const project = JSON.parse(fs.readFileSync(path.join(__dirname, '../project.config.json'), 'utf8'))
  assert.equal(config.appId, 'touristappid')
  assert.equal(config.apiBase, '')
  assert.equal(config.allowInsecureDev, false)
  assert.equal(project.appid, 'touristappid')
  assert.equal(project.setting.urlCheck, true)
})

test('HTTPS and loopback rules', function () {
  assert.equal(api.resolveRequest(config, '/v1/events').code, 'API_BASE_MISSING')
  assert.equal(api.resolveRequest({ apiBase: 'http://example.com' }, '/v1/events').code, 'HTTPS_REQUIRED')
  assert.equal(api.resolveRequest({ apiBase: 'http://127.0.0.1:8080', allowInsecureDev: true }, '/v1/events').ok, true)
  assert.equal(api.resolveRequest({ apiBase: 'https://api.example.com/v1' }, '/v1/events').code, 'API_BASE_INVALID')
  const ready = api.resolveRequest({ apiBase: 'https://api.example.com' }, '/v1/auth/wechat')
  assert.equal(ready.url, 'https://api.example.com/v1/auth/wechat')
  assert.deepEqual(api.domainChecklist(ready.host).request, ['api.example.com'])
})

test('locale keys match', function () {
  const base = Object.keys(STR['zh-Hans']).sort()
  for (const locale of locales()) {
    assert.deepEqual(Object.keys(STR[locale]).sort(), base)
    assert.equal(t(locale, 'retracted').length > 0, true)
  }
})

test('wiki hides iceborne entries on the base profile and matches aliases', function () {
  const base = catalog.listEntries(world, { profile: 'base', locale: 'zh-Hans' })
  assert.equal(base.some(function (row) { return row.entryId === 'fixture-ice-elder' }), false)
  assert.equal(base.some(function (row) { return row.entryId === 'fixture-jagras' }), true)
  const ice = catalog.listEntries(world, { profile: 'iceborne', locale: 'zh-Hans' })
  assert.equal(ice.some(function (row) { return row.entryId === 'fixture-ice-elder' }), true)
  const found = catalog.listEntries(world, { profile: 'base', q: 'ＪＡＧＲＡＳ' })
  assert.equal(found.some(function (row) { return row.entryId === 'fixture-jagras' }), true)
  const none = present.wikiModel(world, { profile: 'base', q: '不存在的词', locale: 'zh-Hans' })
  assert.equal(none.empty, true)
  assert.equal(none.emptyText, '没有符合的条目')
})

test('article and map keep layers apart', function () {
  const ore = present.articleModel(world, 'material', 'fixture-iron-ore', 'zh-Hans')
  assert.equal(ore.hasMap, true)
  assert.equal(ore.mapId, 'fixture-ancient-forest')
  const floor1 = present.mapModel(world, { layerId: 'floor-1', selectedPoiId: 'poi-common' })
  const floor2 = present.mapModel(world, { layerId: 'floor-2', selectedPoiId: 'poi-rare' })
  assert.deepEqual(floor1.markers.map(function (m) { return m.poiId }), ['poi-common'])
  assert.deepEqual(floor2.markers.map(function (m) { return m.poiId }), ['poi-rare'])
  assert.equal(floor1.markers[0].left, floor2.markers[0].left)
  assert.equal(floor1.markers[0].on, true)
  const hidden = present.mapModel(world, { layerId: 'floor-1', kinds: [] })
  assert.equal(hidden.markers.length, 0)
})

test('home cards follow the game', function () {
  const home = present.homeModel({ gameId: 'world', profile: 'base', locale: 'zh-Hans', theme: 'light', events: events, pack: { manifest: worldManifest }, apiConfigured: false })
  assert.equal(home.showMap, true)
  assert.equal(home.eventTitle, '夹具赏金：古代树调查')
  assert.match(home.banner, /HTTPS/)
  const wilds = present.homeModel({ gameId: 'wilds', locale: 'zh-Hans', events: events, pack: null, apiConfigured: true })
  assert.equal(wilds.showMap, false)
  assert.equal(wilds.eventEmpty, false)
  assert.equal(wilds.banner, '')
  assert.equal(wilds.packText, '尚未下载')
})

test('events can be found by reward', function () {
  const rows = present.filterEvents(events, { reward: '果实', locale: 'zh-Hans' })
  assert.equal(rows.length, 1)
  assert.equal(rows[0].id, 'fixture-event-ancient')
})

test('public build hides equipment after retraction', function () {
  const open = present.buildDetail(builds[0], 'zh-Hans')
  assert.equal(open.retracted, false)
  assert.equal(open.lines.length > 0, true)
  const gone = present.buildDetail({ retracted: true, title: '夹具公开配装', snapshot: builds[0].snapshot }, 'zh-Hans')
  assert.equal(gone.title, '这份配装已撤回')
  assert.equal(gone.lines.length, 0)
})

test('wx.login stops cleanly without credentials', async function () {
  const missing = await auth.login({
    wx: { login: async function () { return { code: 'js-code' } } },
    request: async function () { throw new Error('should not send') },
    config: config
  })
  assert.equal(missing.code, 'API_BASE_MISSING')
  const blocked = await auth.login({
    wx: { login: async function () { return { code: 'js-code' } } },
    request: async function () { return { statusCode: 503, data: { code: 'WECHAT_NOT_CONFIGURED' } } },
    config: { apiBase: 'https://api.example.com' }
  })
  assert.equal(blocked.code, 'WECHAT_NOT_CONFIGURED')
  const account = present.accountModel({ locale: 'zh-Hans', loginCode: 'WECHAT_NOT_CONFIGURED' })
  assert.match(account.banner, /AppSecret/)
  assert.equal(account.name, '访客')
})

test('member sync pushes favorites with the bearer token', async function () {
  const local = sync.upsertFavorite({ favorites: [], outbox: [], token: 'tok' }, {
    gameId: 'world', kind: 'monster', entryId: 'fixture-jagras', title: '夹具大凶豺龙'
  }, 'fav-1')
  assert.equal(local.syncStatus, 'pending')
  let sawAuth = ''
  const result = await sync.pushAndSnapshot({
    token: 'tok',
    config: { apiBase: 'https://api.example.com' },
    outbox: local.outbox,
    request: async function (opts) {
      sawAuth = opts.header.Authorization
      if (opts.url.indexOf('/snapshot') >= 0) {
        return { statusCode: 200, data: { watermark: 1, records: [{ recordType: 'favorite', gameId: 'world', kind: 'monster', entryId: 'fixture-jagras', revision: 1, payload: { title: '夹具大凶豺龙' } }] } }
      }
      return { statusCode: 200, data: { results: [{ opId: 'fav-1', status: 'applied' }] } }
    }
  })
  assert.equal(sawAuth, 'Bearer tok')
  assert.equal(result.syncStatus, 'synced')
  assert.equal(result.outbox.length, 0)
  assert.equal(result.favorites[0].entryId, 'fixture-jagras')
  const quota = await sync.loadEntitlement({
    token: 'tok',
    config: { apiBase: 'https://api.example.com' },
    request: async function () { return { statusCode: 200, data: { planId: 'member', quotaBytes: 20000, usedBytes: 12 } } }
  })
  assert.equal(quota.quotaBytes, 20000)
})

test('reminders stay on device when the API is missing and fire before start', async function () {
  const event = events[0]
  const saved = reminders.followLocal([], event, 'zh-Hans', '2026-11-23T00:00:00Z', 'revoke-1')
  assert.equal(saved.row.where, 'local')
  const again = reminders.followLocal(saved.reminders, event, 'zh-Hans', '2026-11-23T00:00:00Z', 'other')
  assert.equal(again.already, true)
  const due = reminders.dueReminders(saved.reminders, Date.parse('2026-11-23T00:00:00Z'))
  assert.equal(due.length, 1)
  assert.match(reminders.calendarText(event, 'zh-Hans'), /UID:fixture-event-ancient@mhbuddy/)
  const remote = await reminders.subscribe({
    config: config,
    event: event,
    revokeToken: 'revoke-1',
    request: async function () { throw new Error('offline') }
  })
  assert.equal(remote.code, 'API_BASE_MISSING')
})

test('fixture pack signature matches the manifest', function () {
  const checked = integrity.verifyPack(worldManifest, worldText, pub, nacl)
  assert.equal(checked.ok, true)
  assert.equal(checked.hash, worldManifest.sha256)
  const bad = integrity.verifyPack(Object.assign({}, worldManifest, { signature: 'aaaa' }), worldText, pub, nacl)
  assert.equal(bad.code, 'BAD_SIGNATURE')
  const store = cache.memoryStore()
  const saved = cache.savePack(store, 'world', {
    revisionNumber: 2,
    manifest: worldManifest,
    catalog: checked.catalog,
    savedAt: '2026-11-23T00:00:00Z',
    hash: checked.hash
  })
  assert.equal(saved.ok, true)
  const stale = cache.savePack(store, 'world', { revisionNumber: 1, manifest: worldManifest, catalog: world, hash: checked.hash })
  assert.equal(stale.code, 'STALE_REVISION')
  assert.equal(cache.chooseCatalog(world, cache.loadPack(store, 'world')).source, 'cache')
})

test('download keeps the raw body for the hash', async function () {
  const result = await packs.downloadPack({
    gameId: 'world',
    clientVersion: '0.1.0',
    config: { apiBase: 'https://api.example.com' },
    publicKeyHex: pub,
    nacl: nacl,
    request: async function (opts) {
      if (opts.url.indexOf('/v1/packs/latest') >= 0) return { statusCode: 200, data: worldManifest }
      assert.equal(opts.dataType, 'text')
      return { statusCode: 200, data: worldText }
    }
  })
  assert.equal(result.ok, true)
  assert.equal(result.catalog.gameId, 'world')
})

test('mini program pages and icons exist', function () {
  const app = JSON.parse(fs.readFileSync(path.join(__dirname, '../miniprogram/app.json'), 'utf8'))
  for (const page of app.pages) {
    for (const ext of ['.js', '.json', '.wxml', '.wxss']) {
      assert.equal(fs.existsSync(path.join(__dirname, '../miniprogram', page + ext)), true, page + ext)
    }
  }
  for (const icon of ['home', 'wiki', 'builds', 'me']) {
    assert.equal(fs.existsSync(path.join(__dirname, '../miniprogram/icons', icon + '.png')), true)
    assert.equal(fs.existsSync(path.join(__dirname, '../miniprogram/icons', icon + '-on.png')), true)
  }
  const bundled = fs.readFileSync(path.join(__dirname, '../miniprogram/data/catalog-world.json'))
  const source = fs.readFileSync(path.join(fixtures, 'catalog-world.json'))
  assert.equal(crypto.createHash('sha256').update(bundled).digest('hex'), crypto.createHash('sha256').update(source).digest('hex'))
})
