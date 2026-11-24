const present = require('../../logic/present')
const content = require('../../logic/content')

Page({
  data: { theme: 'light', kinds: ['gather', 'rare-gather'], missing: false },
  onLoad(query) {
    this.query = query || {}
    this.layerId = query.layerId || ''
    this.selected = query.poiId || ''
    this.render()
  },
  catalog() {
    const gameId = (this.query && this.query.gameId) || 'world'
    return content.catalogFor(gameId, wx.getStorageSync('mh-pack-' + gameId)).catalog
  },
  render() {
    const g = getApp().globalData
    const model = present.mapModel(this.catalog(), {
      mapId: this.query.mapId,
      layerId: this.layerId,
      kinds: this.data.kinds,
      selectedPoiId: this.selected,
      locale: g.locale
    })
    if (model.name) wx.setNavigationBarTitle({ title: model.name })
    this.setData(Object.assign({
      theme: g.theme,
      kindGather: this.data.kinds.indexOf('gather') >= 0,
      kindRare: this.data.kinds.indexOf('rare-gather') >= 0
    }, model))
  },
  onLayer(e) {
    this.layerId = e.currentTarget.dataset.id
    this.selected = ''
    this.render()
  },
  onKind(e) {
    const id = e.currentTarget.dataset.id
    const kinds = this.data.kinds.slice()
    const idx = kinds.indexOf(id)
    if (idx >= 0) kinds.splice(idx, 1)
    else kinds.push(id)
    this.data.kinds = kinds
    this.render()
  },
  onPin(e) {
    this.selected = e.currentTarget.dataset.id
    this.render()
  },
  openEntry() {
    const sel = this.data.selected
    if (!sel || !sel.resourceId) return
    const gameId = (this.query && this.query.gameId) || 'world'
    wx.navigateTo({ url: '/pages/wiki/article?gameId=' + gameId + '&kind=' + sel.resourceKind + '&entryId=' + sel.resourceId })
  }
})
