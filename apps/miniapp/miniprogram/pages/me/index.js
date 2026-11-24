const present = require('../../logic/present')
const auth = require('../../logic/auth')
const sync = require('../../logic/sync')
const wxapi = require('../../logic/wxapi')
const i18n = require('../../logic/i18n')

Page({
  data: { theme: 'light' },
  onShow() { this.render() },
  render() {
    const g = getApp().globalData
    const model = present.accountModel({
      locale: g.locale,
      theme: g.theme,
      session: g.session,
      syncStatus: g.syncStatus,
      favorites: g.favorites,
      loginCode: g.loginCode,
      entitlement: g.entitlement
    })
    const quota = g.entitlement ? (g.entitlement.usedBytes + ' / ' + g.entitlement.quotaBytes) : '未开通'
    this.setData(Object.assign({
      locale: g.locale,
      locales: i18n.locales(),
      quota: quota,
      favoriteLabel: i18n.t(g.locale, 'favorites'),
      memberLabel: i18n.t(g.locale, 'memberSpace'),
      syncLabel: i18n.t(g.locale, 'syncNow')
    }, model))
  },
  login() {
    const app = getApp()
    const g = app.globalData
    auth.login({ wx: wxapi, request: wxapi.request, config: g.config }).then(function (res) {
      g.loginCode = res.ok ? '' : res.code
      if (!res.ok) {
        app.savePrefs()
        this.render()
        return
      }
      g.session = { userId: res.userId, displayName: res.displayName, token: res.token, mode: res.mode }
      g.syncStatus = 'syncing'
      app.savePrefs()
      app.saveLibrary()
      this.render()
      return sync.pushAndSnapshot({ request: wxapi.request, config: g.config, token: res.token, outbox: g.outbox })
    }.bind(this)).then(function (res) {
      if (!res) return
      const g = getApp().globalData
      if (res.favorites) g.favorites = res.favorites
      g.outbox = res.outbox || g.outbox
      g.syncStatus = res.syncStatus || g.syncStatus
      getApp().saveLibrary()
      return sync.loadEntitlement({ request: wxapi.request, config: g.config, token: g.session.token })
    }.bind(this)).then(function (ent) {
      if (!ent || !ent.ok) {
        this.render()
        return
      }
      getApp().globalData.entitlement = ent
      this.render()
    }.bind(this)).catch(function () {
      getApp().globalData.syncStatus = 'pending'
      getApp().saveLibrary()
      this.render()
    }.bind(this))
  },
  logout() {
    const app = getApp()
    const g = app.globalData
    const token = g.session && g.session.token
    g.session = null
    g.entitlement = null
    g.syncStatus = 'local'
    g.loginCode = ''
    app.savePrefs()
    app.saveLibrary()
    this.render()
    if (!token) return
    const gate = require('../../logic/api').resolveRequest(g.config, '/v1/auth/session')
    if (!gate.ok) return
    wxapi.request({ url: gate.url, method: 'DELETE', header: { Authorization: 'Bearer ' + token } }).catch(function () {})
  },
  setLocale(e) {
    getApp().globalData.locale = e.currentTarget.dataset.id
    getApp().savePrefs()
    this.render()
  },
  setTheme(e) {
    getApp().globalData.theme = e.currentTarget.dataset.id
    getApp().savePrefs()
    this.render()
  },
  sync() { this.login() }
})
