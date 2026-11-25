class L10n {
  L10n(this.code);
  final String code;

  static const codes = ['zh-Hans', 'zh-Hant', 'en', 'ja'];

  static const tables = <String, List<String>>{
    'app': ['MH伙伴助手', 'MH夥伴助手', 'MH Buddy', 'MHバディ'],
    'home': ['首页', '首頁', 'Home', 'ホーム'],
    'catalog': ['百科', '百科', 'Wiki', '百科'],
    'builds': ['配装', '配裝', 'Builds', '装備'],
    'me': ['我的', '我的', 'Me', 'マイ'],
    'world': ['世界 / 冰原', '世界 / 冰原', 'World / Iceborne', 'ワールド / アイスボーン'],
    'worldShort': ['世界', '世界', 'World', 'ワールド'],
    'wilds': ['荒野', '荒野', 'Wilds', 'ワイルズ'],
    'offline': ['离线资料', '離線資料', 'Offline data', 'オフライン'],
    'viewQuest': ['查看任务', '查看任務', 'View quest', '任務を見る'],
    'openMap': ['打开地图', '打開地圖', 'Open map', 'マップを開く'],
    'viewUpdate': ['查看更新', '查看更新', 'View update', '更新を見る'],
    'noEvent': ['当前没有限时任务', '目前沒有限時任務', 'No timed quests', '時限任務はありません'],
    'emptyList': ['没有符合的条目', '沒有符合的條目', 'No matching entries', '該当なし'],
    'clearFilters': ['清除筛选', '清除篩選', 'Clear filters', '条件を消す'],
    'retractedTitle': ['这份配装已撤回', '這份配裝已撤回', 'This build was retracted', 'この装備は取り下げられました'],
    'copyMine': ['复制到我的配装', '複製到我的配裝', 'Copy to my builds', '自分の装備へ'],
    'guest': ['访客', '訪客', 'Guest', 'ゲスト'],
    'guestHint': ['收藏和配装保存在这台浏览器。', '收藏和配裝保存在這台瀏覽器。', 'Favorites and builds stay in this browser.', 'お気に入りと装備はこのブラウザに保存されます。'],
    'loginSync': ['登录以同步', '登入以同步', 'Sign in to sync', '同期するにはログイン'],
    'notEnabled': ['未开通', '未開通', 'Not enabled', '未加入'],
    'retry': ['重试', '重試', 'Retry', '再試行'],
    'notDownloaded': ['尚未下载', '尚未下載', 'Not downloaded yet', '未ダウンロード'],
    'viewMaterial': ['查看素材', '查看素材', 'View material', '素材を見る'],
    'fixture': ['夹具资料，不是游戏实数', '夾具資料，不是遊戲實數', 'Fixture data, not live game numbers', 'フィクスチャ。ゲームの実数ではない'],
    'search': ['搜索名称或别名', '搜尋名稱或別名', 'Search names or aliases', '名前・別名を検索'],
    'searchHome': ['搜索武器、怪物、素材', '搜尋武器、怪物、素材', 'Search weapons, monsters, materials', '武器・モンスター・素材'],
    'searchWiki': ['搜索百科', '搜尋百科', 'Search the wiki', '百科を検索'],
    'favorite': ['收藏', '收藏', 'Save', '保存'],
    'favorited': ['已收藏', '已收藏', 'Saved', '保存済み'],
    'map': ['地图查看', '地圖查看', 'View map', 'マップ'],
    'layer': ['楼层', '樓層', 'Layer', '階層'],
    'rare': ['稀有采集', '稀有採集', 'Rare gather', '稀少採取'],
    'allPoints': ['全部点位', '全部點位', 'All points', 'すべての地点'],
    'solve': ['搜索配装', '搜尋配裝', 'Search builds', '装備検索'],
    'stop': ['停止搜索', '停止搜尋', 'Stop', '停止'],
    'saveBuild': ['保存当前配装', '保存目前配裝', 'Save build', '装備を保存'],
    'noResult': ['当前条件无解', '目前條件無解', 'No build matches', '該当なし'],
    'partial': ['未搜完，以下是已有结果', '未搜完，以下是已有結果', 'Search stopped early', '途中結果'],
    'import': ['导入配装文本', '匯入配裝文字', 'Import build text', '装備テキストを読み込む'],
    'preview': ['预览', '預覽', 'Preview', 'プレビュー'],
    'events': ['活动', '活動', 'Events', 'イベント'],
    'eventCard': ['活动任务', '活動任務', 'Event quests', 'イベント'],
    'dataCard': ['资料', '資料', 'Data', 'データ'],
    'rewardSearch': ['按报酬搜索', '按報酬搜尋', 'Search reward', '報酬で検索'],
    'subscribe': ['订阅提醒', '訂閱提醒', 'Subscribe', '通知を購読'],
    'calendar': ['下载日历', '下載日曆', 'Download calendar', 'カレンダー'],
    'verified': ['核实时间', '核實時間', 'Verified', '確認時刻'],
    'language': ['语言', '語言', 'Language', '言語'],
    'theme': ['主题', '主題', 'Theme', 'テーマ'],
    'themeLight': ['羊皮纸（默认）', '羊皮紙（預設）', 'Parchment (default)', '羊皮紙（既定）'],
    'themeDark': ['深色（可选）', '深色（可選）', 'Dark (optional)', 'ダーク（任意）'],
    'login': ['会员登录', '會員登入', 'Member sign in', '会員ログイン'],
    'logout': ['退出', '登出', 'Sign out', 'ログアウト'],
    'sync': ['同步', '同步', 'Sync', '同期'],
    'download': ['下载离线资料', '下載離線資料', 'Download offline data', 'オフライン資料'],
    'offlineReady': ['可离线使用', '可離線使用', 'Ready offline', 'オフライン可'],
    'profileBase': ['本体', '本體', 'Base', '本編'],
    'profileIce': ['冰原', '冰原', 'Iceborne', 'アイスボーン'],
    'openSlots': ['空孔', '空孔', 'Open slots', '空きスロット'],
    'weaponSlots': ['武器空孔', '武器空孔', 'Weapon slots', '武器スロット'],
    'armorSlots': ['防具空孔', '防具空孔', 'Armor slots', '防具スロット'],
    'reserve': ['预留武器孔', '預留武器孔', 'Reserve weapon slot', '武器穴を予約'],
    'useJewels': ['只用我的装饰品', '只用我的裝飾品', 'Use my decorations', '所持装飾品だけ'],
    'hall': ['配装大厅', '配裝大廳', 'Build hall', '装備ホール'],
    'retracted': ['这份公开配装已撤回', '這份公開配裝已撤回', 'This public build was retracted', '公開装備は取り下げられました'],
    'missing': ['没有这条公开记录', '沒有這條公開紀錄', 'No public record', '公開記録がありません'],
    'copyLink': ['复制链接', '複製連結', 'Copy link', 'リンクをコピー'],
    'fieldError': ['条件冲突', '條件衝突', 'Conflicting filters', '条件が矛盾'],
    'draft': ['草稿', '草稿', 'Draft', '下書き'],
    'rarity': ['稀有度', '稀有度', 'Rarity', 'レア度'],
    'source': ['来源', '來源', 'Source', '出典'],
    'privacy': ['隐私说明', '隱私說明', 'Privacy', 'プライバシー'],
  };

  String t(String key) {
    final row = tables[key];
    if (row == null) return key;
    final i = codes.indexOf(code);
    return row[i < 0 ? 0 : i];
  }

  static void check() {
    for (final row in tables.values) {
      if (row.length != codes.length) {
        throw StateError('locale row length');
      }
    }
  }
}
