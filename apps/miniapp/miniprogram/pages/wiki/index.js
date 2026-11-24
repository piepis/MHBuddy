const present = require('../../logic/present')
const content = require('../../logic/content')

Page({
  data: { q: '', kind: '', theme: 'light', rows: [], kinds: [] },
  onShow() {
    const g = getApp().globalData
    const q = g.wikiQuery || this.data.q
    g.wikiQuery = ''
    this.setData({ q: q, theme: g.theme })
    this.render()
  },
  render() {
    const g = getApp().globalData
    const chosen = content.catalogFor(g.gameId, wx.getStorageSync('mh-pack-' + g.gameId))
    const model = present.wikiModel(chosen.catalog, {
      kind: this.data.kind,
      q: this.data.q,
      profile: g.profile,
      locale: g.locale
    })
    this.setData({ rows: model.rows, empty: model.empty, emptyText: model.emptyText, clearText: model.clearText, kinds: model.kinds, theme: g.theme })
  },
  onInput(e) {
    this.setData({ q: e.detail.value })
    this.render()
  },
  onKind(e) {
    this.setData({ kind: e.currentTarget.dataset.id })
    this.render()
  },
  clear() {
    this.setData({ q: '', kind: '' })
    this.render()
  },
  open(e) {
    const g = getApp().globalData
    const ds = e.currentTarget.dataset
    wx.navigateTo({ url: '/pages/wiki/article?gameId=' + g.gameId + '&kind=' + ds.kind + '&entryId=' + ds.id })
  }
})
