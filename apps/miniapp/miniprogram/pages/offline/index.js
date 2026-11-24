const content = require('../../logic/content')
const packs = require('../../logic/packs')
const cache = require('../../logic/cache')
const wxapi = require('../../logic/wxapi')
const key = require('../../logic/fixture-key')
const nacl = require('../../vendor/tweetnacl')

Page({
  data: { theme: 'light', rows: [] },
  onShow() { this.render() },
  render() {
    const g = getApp().globalData
    const games = ['world', 'wilds']
    const rows = games.map(function (gameId) {
      const bundled = content.bundledPack(gameId)
      const cached = wx.getStorageSync('mh-pack-' + gameId)
      const pack = cached && cached.revisionNumber >= bundled.revisionNumber ? cached : bundled
      return {
        gameId: gameId,
        name: gameId === 'world' ? '世界 / 冰原' : '荒野',
        revision: (pack.manifest && pack.manifest.dataRevision) || '',
        verified: pack.savedAt || '随包',
        fixture: !!(pack.manifest && pack.manifest.fixture),
        error: ''
      }
    })
    this.setData({ theme: g.theme, rows: rows, banner: g.config.apiBase ? '' : '未配置 HTTPS 接口。随包夹具可以离线阅读，不能从服务器更新。' })
  },
  download(e) {
    const gameId = e.currentTarget.dataset.id
    const g = getApp().globalData
    const rows = this.data.rows.map(function (row) {
      return row.gameId === gameId ? Object.assign({}, row, { error: '' }) : row
    })
    this.setData({ rows: rows })
    packs.downloadPack({
      config: g.config,
      gameId: gameId,
      clientVersion: g.config.clientVersion,
      publicKeyHex: key.fixturePublicKeyHex,
      nacl: nacl,
      request: wxapi.request
    }).then(function (res) {
      if (!res.ok) {
        this.setError(gameId, res.code || 'PACK_FAILED')
        return
      }
      const store = {
        get: function (k) { return k === 'pack:' + gameId ? wx.getStorageSync('mh-pack-' + gameId) : null },
        set: function (k, value) { wx.setStorageSync('mh-pack-' + gameId, value) }
      }
      const saved = cache.savePack(store, gameId, {
        revisionNumber: res.revisionNumber,
        manifest: res.manifest,
        catalog: res.catalog,
        savedAt: new Date().toISOString(),
        hash: res.hash
      })
      if (!saved.ok) this.setError(gameId, saved.code)
      this.render()
    }.bind(this)).catch(function () {
      this.setError(gameId, 'NETWORK')
    }.bind(this))
  },
  setError(gameId, code) {
    const rows = this.data.rows.map(function (row) {
      return row.gameId === gameId ? Object.assign({}, row, { error: code }) : row
    })
    this.setData({ rows: rows })
  }
})
