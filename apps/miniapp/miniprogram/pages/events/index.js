const content = require('../../logic/content')
const present = require('../../logic/present')

Page({
  data: { theme: 'light', q: '', rows: [] },
  onShow() { this.render() },
  render() {
    const g = getApp().globalData
    const rows = present.filterEvents(content.events(), { gameId: g.gameId, q: this.data.q, locale: g.locale })
    this.setData({
      theme: g.theme,
      rows: rows.map(function (event) {
        return { id: event.id, title: require('../../logic/catalog').textOf(event.titles, g.locale), meta: event.timezone || '' }
      })
    })
  },
  onInput(e) {
    this.setData({ q: e.detail.value })
    this.render()
  },
  open(e) {
    wx.navigateTo({ url: '/pages/events/detail?id=' + e.currentTarget.dataset.id })
  }
})
