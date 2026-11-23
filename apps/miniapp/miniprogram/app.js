const config = require('./config')

App({
  globalData: {
    config: config,
    gameId: 'world',
    profile: 'base',
    locale: config.defaultLocale,
    theme: config.defaultTheme,
    session: null,
    favorites: [],
    outbox: [],
    reminders: [],
    syncStatus: 'local',
    wikiQuery: '',
    loginCode: ''
  },
  onLaunch() {
    try {
      const prefs = wx.getStorageSync('mh-prefs') || {}
      const library = wx.getStorageSync('mh-library') || {}
      const g = this.globalData
      if (prefs.gameId === 'world' || prefs.gameId === 'wilds') g.gameId = prefs.gameId
      if (prefs.profile === 'base' || prefs.profile === 'iceborne') g.profile = prefs.profile
      if (prefs.locale) g.locale = prefs.locale
      if (prefs.theme === 'light' || prefs.theme === 'dark') g.theme = prefs.theme
      if (prefs.session && prefs.session.token) g.session = prefs.session
      g.favorites = library.favorites || []
      g.outbox = library.outbox || []
      g.reminders = library.reminders || []
      const legacy = { '仅本地': 'local', '同步中': 'syncing', '已同步': 'synced', '待处理': 'pending' }
      g.syncStatus = legacy[library.syncStatus] || library.syncStatus || (g.session ? 'pending' : 'local')
    } catch (err) {}
  },
  savePrefs() {
    const g = this.globalData
    wx.setStorageSync('mh-prefs', {
      gameId: g.gameId,
      profile: g.profile,
      locale: g.locale,
      theme: g.theme,
      session: g.session
    })
  },
  saveLibrary() {
    const g = this.globalData
    wx.setStorageSync('mh-library', {
      favorites: g.favorites,
      outbox: g.outbox,
      reminders: g.reminders,
      syncStatus: g.syncStatus
    })
  }
})
