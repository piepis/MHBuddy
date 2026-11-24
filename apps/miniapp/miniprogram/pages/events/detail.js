const content = require('../../logic/content')
const catalog = require('../../logic/catalog')
const reminders = require('../../logic/reminders')
const wxapi = require('../../logic/wxapi')

function token() {
  return Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2)
}

Page({
  data: { theme: 'light', following: false },
  onLoad(query) {
    const g = getApp().globalData
    const event = content.events().filter(function (row) { return row.id === query.id })[0]
    this.event = event
    if (!event) {
      this.setData({ missing: true, theme: g.theme })
      return
    }
    const rewards = (event.rewards || []).map(function (item) { return catalog.textOf(item.names, g.locale) })
    const following = (g.reminders || []).some(function (row) { return row.eventId === event.id })
    wx.setNavigationBarTitle({ title: catalog.textOf(event.titles, g.locale) })
    this.setData({
      theme: g.theme,
      missing: false,
      title: catalog.textOf(event.titles, g.locale),
      meta: [event.gameId, event.platformId, event.verifiedAt ? '核实 ' + event.verifiedAt : ''].filter(Boolean).join(' · '),
      conditions: event.conditions || '',
      when: (event.startsAt || '') + ' – ' + (event.endsAt || ''),
      timezone: event.timezone || '',
      rewards: rewards,
      following: following,
      note: event.fixture ? '夹具日程，不是官方时间。' : ''
    })
  },
  follow() {
    if (!this.event || this.data.following) return
    const app = getApp()
    const g = app.globalData
    const revoke = token()
    const local = reminders.followLocal(g.reminders, this.event, g.locale, new Date().toISOString(), revoke)
    g.reminders = local.reminders
    app.saveLibrary()
    this.setData({ following: true, followNote: '已记在这台手机。服务器域名配好之前不会推送。' })
    reminders.subscribe({
      config: g.config,
      token: g.session && g.session.token,
      event: this.event,
      revokeToken: revoke,
      request: wxapi.request
    }).then(function (res) {
      if (!res.ok) return
      g.reminders = reminders.markSynced(g.reminders, this.event.id, res.id)
      app.saveLibrary()
      this.setData({ followNote: '已同步到账户。' })
    }.bind(this)).catch(function () {})
  },
  copyCalendar() {
    if (!this.event) return
    const g = getApp().globalData
    wx.setClipboardData({ data: reminders.calendarText(this.event, g.locale) })
  }
})
