const content = require('../../logic/content')
const api = require('../../logic/api')
const wxapi = require('../../logic/wxapi')

Page({
  data: { theme: 'light', rows: [], banner: '' },
  onShow() { this.load() },
  load() {
    const g = getApp().globalData
    const local = content.publicBuilds().filter(function (row) { return row.gameId === g.gameId })
    this.setData({
      theme: g.theme,
      rows: local.map(function (row) {
        return { id: row.id, title: row.title, meta: row.weaponType + ' · ' + row.rarity }
      }),
      banner: api.resolveRequest(g.config, '/v1/public-builds').ok ? '' : '未配置 HTTPS 接口。下面是随包的公开配装夹具。'
    })
    const gate = api.resolveRequest(g.config, '/v1/public-builds?gameId=' + g.gameId)
    if (!gate.ok) return
    wxapi.request({ url: gate.url, method: 'GET' }).then(function (res) {
      if (res.statusCode !== 200 || !res.data || !res.data.builds) return
      this.setData({
        rows: res.data.builds.map(function (row) {
          return { id: row.id, title: row.title, meta: (row.weaponType || '') + ' · ' + (row.rarity || '') }
        }),
        banner: ''
      })
    }.bind(this)).catch(function () {})
  },
  open(e) {
    wx.navigateTo({ url: '/pages/builds/detail?id=' + e.currentTarget.dataset.id })
  }
})
