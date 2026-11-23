const content = require('../../logic/content')
const present = require('../../logic/present')
const api = require('../../logic/api')
const wxapi = require('../../logic/wxapi')

Page({
  data: { theme: 'light', lines: [] },
  onLoad(query) {
    const g = getApp().globalData
    const local = content.publicBuilds().filter(function (row) { return row.id === query.id })[0]
    this.show(local || null, g)
    const gate = api.resolveRequest(g.config, '/v1/public-builds/' + query.id)
    if (!gate.ok) return
    wxapi.request({ url: gate.url, method: 'GET' }).then(function (res) {
      if (res.statusCode === 410) this.show({ retracted: true }, g)
      else if (res.statusCode === 200) this.show(res.data, g)
      else if (res.statusCode === 404) this.show(null, g)
    }.bind(this)).catch(function () {})
  },
  show(record, g) {
    const model = present.buildDetail(record, g.locale)
    wx.setNavigationBarTitle({ title: model.title || '公开配装' })
    const tags = model.tags || []
    this.setData(Object.assign({ theme: g.theme, tagsText: tags.join(' · ') }, model))
  }
})
