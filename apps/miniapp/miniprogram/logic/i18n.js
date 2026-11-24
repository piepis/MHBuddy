'use strict'

const STR = {
  'zh-Hans': {
    home: '首页', wiki: '百科', builds: '配装', me: '我的',
    searchPlaceholder: '搜索武器、怪物、素材',
    viewEvent: '查看任务', viewUpdate: '查看更新', openMap: '打开地图',
    noEvent: '当前没有限时任务', noEntries: '没有符合的条目', clearFilters: '清除筛选',
    retracted: '这份配装已撤回', notDownloaded: '尚未下载', offlineReady: '可离线阅读',
    login: '登录以同步', guest: '访客', guestHint: '收藏和提醒保存在这台手机。',
    localOnly: '仅本地', syncing: '同步中', synced: '已同步', pending: '待处理',
    follow: '关注', following: '已关注', retry: '重试',
    fixtureNote: '夹具数据，不是游戏实数。',
    apiMissing: '未配置 HTTPS 接口。当前阅读随包夹具，登录和会员同步还不可用。',
    wechatBlocked: '微信登录还不能兑换。所有者需要在服务端配置 AppID 和 AppSecret。',
    download: '下载', update: '更新', copyCalendar: '复制日历',
    memberSpace: '会员空间', favorites: '收藏', language: '语言', theme: '外观',
    light: '浅色', dark: '深色', world: '世界', wilds: '荒野', base: '本体', iceborne: '冰原',
    all: '全部', weapon: '武器', armor: '防具', monster: '怪物', item: '道具', skill: '技能',
    reward: '报酬', mapView: '地图查看', layerMissing: '这一层尚未下载',
    noPublic: '没有这条公开记录', copyBuild: '复制到我的配装', syncNow: '同步',
    logout: '退出', followedLocal: '已记在这台手机。服务器域名配好之前不会推送。'
  },
  'zh-Hant': {
    home: '首頁', wiki: '百科', builds: '配裝', me: '我的',
    searchPlaceholder: '搜尋武器、怪物、素材',
    viewEvent: '查看任務', viewUpdate: '查看更新', openMap: '打開地圖',
    noEvent: '目前沒有限時任務', noEntries: '沒有符合的條目', clearFilters: '清除篩選',
    retracted: '這份配裝已撤回', notDownloaded: '尚未下載', offlineReady: '可離線閱讀',
    login: '登入以同步', guest: '訪客', guestHint: '收藏和提醒保存在這台手機。',
    localOnly: '僅本地', syncing: '同步中', synced: '已同步', pending: '待處理',
    follow: '關注', following: '已關注', retry: '重試',
    fixtureNote: '夾具資料，不是遊戲實數。',
    apiMissing: '未設定 HTTPS 介面。目前閱讀隨包夾具，登入和會員同步還不可用。',
    wechatBlocked: '微信登入還不能兌換。所有者需要在伺服器設定 AppID 和 AppSecret。',
    download: '下載', update: '更新', copyCalendar: '複製日曆',
    memberSpace: '會員空間', favorites: '收藏', language: '語言', theme: '外觀',
    light: '淺色', dark: '深色', world: '世界', wilds: '荒野', base: '本體', iceborne: '冰原',
    all: '全部', weapon: '武器', armor: '防具', monster: '怪物', item: '道具', skill: '技能',
    reward: '報酬', mapView: '地圖查看', layerMissing: '這一層尚未下載',
    noPublic: '沒有這條公開紀錄', copyBuild: '複製到我的配裝', syncNow: '同步',
    logout: '登出', followedLocal: '已記在這台手機。伺服器網域配好之前不會推送。'
  },
  en: {
    home: 'Home', wiki: 'Wiki', builds: 'Builds', me: 'Me',
    searchPlaceholder: 'Search weapons, monsters, materials',
    viewEvent: 'View quest', viewUpdate: 'View update', openMap: 'Open map',
    noEvent: 'No limited quest right now', noEntries: 'No matching entries', clearFilters: 'Clear filters',
    retracted: 'This build was retracted', notDownloaded: 'Not downloaded yet', offlineReady: 'Available offline',
    login: 'Sign in to sync', guest: 'Guest', guestHint: 'Favorites and reminders stay on this phone.',
    localOnly: 'On this phone', syncing: 'Syncing', synced: 'Synced', pending: 'Pending',
    follow: 'Follow', following: 'Following', retry: 'Retry',
    fixtureNote: 'Fixture data, not live game numbers.',
    apiMissing: 'No HTTPS API is configured. Bundled fixtures stay readable. Sign-in and member sync are unavailable.',
    wechatBlocked: 'WeChat sign-in cannot be exchanged yet. The owner must set the AppID and AppSecret on the server.',
    download: 'Download', update: 'Update', copyCalendar: 'Copy calendar',
    memberSpace: 'Member space', favorites: 'Favorites', language: 'Language', theme: 'Appearance',
    light: 'Light', dark: 'Dark', world: 'World', wilds: 'Wilds', base: 'Base', iceborne: 'Iceborne',
    all: 'All', weapon: 'Weapons', armor: 'Armor', monster: 'Monsters', item: 'Items', skill: 'Skills',
    reward: 'Reward', mapView: 'View on map', layerMissing: 'This layer is not downloaded',
    noPublic: 'No public record', copyBuild: 'Copy to my builds', syncNow: 'Sync',
    logout: 'Sign out', followedLocal: 'Saved on this phone. It will not push until the server domain is configured.'
  },
  ja: {
    home: 'ホーム', wiki: '図鑑', builds: '装備', me: 'マイ',
    searchPlaceholder: '武器、モンスター、素材を検索',
    viewEvent: 'クエストを見る', viewUpdate: '更新を見る', openMap: 'マップを開く',
    noEvent: '期間限定クエストはありません', noEntries: '一致する項目がありません', clearFilters: '条件をクリア',
    retracted: 'この装備は取り下げられました', notDownloaded: '未ダウンロード', offlineReady: 'オフラインで読めます',
    login: 'ログインして同期', guest: 'ゲスト', guestHint: 'お気に入りと通知はこの端末に保存されます。',
    localOnly: 'この端末のみ', syncing: '同期中', synced: '同期済み', pending: '未処理',
    follow: 'フォロー', following: 'フォロー中', retry: '再試行',
    fixtureNote: 'フィクスチャです。ゲームの実数ではありません。',
    apiMissing: 'HTTPS の API が未設定です。同梱フィクスチャは読めます。ログインと会員同期は使えません。',
    wechatBlocked: '微信ログインはまだ交換できません。所有者がサーバーに AppID と AppSecret を設定する必要があります。',
    download: 'ダウンロード', update: '更新', copyCalendar: 'カレンダーをコピー',
    memberSpace: '会員スペース', favorites: 'お気に入り', language: '言語', theme: '外観',
    light: 'ライト', dark: 'ダーク', world: 'ワールド', wilds: 'ワイルズ', base: '本編', iceborne: 'アイスボーン',
    all: 'すべて', weapon: '武器', armor: '防具', monster: 'モンスター', item: 'アイテム', skill: 'スキル',
    reward: '報酬', mapView: 'マップで見る', layerMissing: 'この層は未ダウンロードです',
    noPublic: '公開記録がありません', copyBuild: '自分の装備にコピー', syncNow: '同期',
    logout: 'ログアウト', followedLocal: 'この端末に保存しました。サーバードメインを設定するまで推送しません。'
  }
}

function t(locale, key) {
  const pack = STR[locale] || STR['zh-Hans']
  if (pack[key]) return pack[key]
  return STR['zh-Hans'][key] || key
}

function locales() {
  return Object.keys(STR)
}

module.exports = { t, locales, STR }
