const present = require('../../logic/present')
const content = require('../../logic/content')
const api = require('../../logic/api')

function state() {
  return getApp().globalData
}

Page({
  data: {},
  onShow() { this.render() },
  render() {
    const g = state()
    const model = present.homeModel({
      gameId: g.gameId,
      profile: g.profile,
      locale: g.locale,
      theme: g.theme,
      events: content.events(),
      pack: content.bundledPack(g.gameId),
      apiConfigured: api.resolveRequest(g.config, '/v1/events').ok
    })
    this.setData(model)
  },
  onGame(e) {
    const g = state()
    g.gameId = e.currentTarget.dataset.id
    if (g.gameId !== 'world') g.profile = 'base'
    getApp().savePrefs()
    this.render()
  },
  onProfile(e) {
    state().profile = e.currentTarget.dataset.id
    getApp().savePrefs()
    this.render()
  },
  onSearch(e) {
    state().wikiQuery = e.detail.value || ''
    wx.switchTab({ url: '/pages/wiki/index' })
  },
  openEvents() {
    if (!this.data.eventId) return
    wx.navigateTo({ url: '/pages/events/index' })
  },
  openMap() {
    wx.navigateTo({ url: '/pages/map/index?gameId=world' })
  },
  openOffline() {
    wx.navigateTo({ url: '/pages/offline/index' })
  }
})
