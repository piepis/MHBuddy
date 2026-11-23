const present = require('../../logic/present')
const content = require('../../logic/content')
const sync = require('../../logic/sync')

Page({
  data: { theme: 'light', missing: true },
  onLoad(query) {
    this.query = query || {}
    const g = getApp().globalData
    const chosen = content.catalogFor(query.gameId || g.gameId, wx.getStorageSync('mh-pack-' + (query.gameId || g.gameId)))
    const model = present.articleModel(chosen.catalog, query.kind, query.entryId, g.locale)
    const fav = (g.favorites || []).some(function (row) {
      return row.gameId === (query.gameId || g.gameId) && row.kind === query.kind && row.entryId === query.entryId
    })
    wx.setNavigationBarTitle({ title: model.name || '百科' })
    this.setData(Object.assign({ theme: g.theme, fav: fav, gameId: query.gameId || g.gameId }, model))
  },
  toggleFav() {
    if (this.data.missing) return
    const app = getApp()
    const g = app.globalData
    const next = sync.upsertFavorite({
      favorites: g.favorites,
      outbox: g.outbox,
      token: g.session && g.session.token
    }, {
      gameId: this.data.gameId,
      kind: this.query.kind,
      entryId: this.query.entryId,
      title: this.data.name
    }, 'fav-' + Date.now())
    g.favorites = next.favorites
    g.outbox = next.outbox
    g.syncStatus = next.syncStatus
    app.saveLibrary()
    this.setData({ fav: true })
    if (g.session && g.session.token) this.push()
  },
  push() {
    const app = getApp()
    const g = app.globalData
    g.syncStatus = 'syncing'
    app.saveLibrary()
    sync.pushAndSnapshot({
      request: require('../../logic/wxapi').request,
      config: g.config,
      token: g.session.token,
      outbox: g.outbox
    }).then(function (res) {
      if (res.favorites) g.favorites = res.favorites
      g.outbox = res.outbox || []
      g.syncStatus = res.syncStatus
      app.saveLibrary()
    }).catch(function () {
      g.syncStatus = 'pending'
      app.saveLibrary()
    })
  },
  openMap() {
    if (!this.data.hasMap) return
    wx.navigateTo({
      url: '/pages/map/index?gameId=' + this.data.gameId + '&mapId=' + this.data.mapId + '&poiId=' + this.data.poiId + '&layerId=' + this.data.layerId
    })
  }
})
