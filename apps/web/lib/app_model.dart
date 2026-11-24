import 'dart:async';
import 'dart:convert';

import 'package:builds/builds.dart';
import 'package:catalog/catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:player_store/player_store.dart';

import 'data/vault.dart';
import 'net/api.dart';
import 'theme.dart';

class AppModel extends ChangeNotifier {
  AppModel({Api? api, Vault? vault})
      : api = api ?? Api(),
        vault = vault ?? Vault();

  final Api api;
  final Vault vault;
  final store = PlayerStore();

  String themeName = 'light';
  String locale = 'zh-Hans';
  String profile = 'base';
  String gameId = 'world';
  Catalog? world;
  Catalog? wilds;
  bool offlineReady = false;
  String? userId;
  String? status;
  bool ready = false;
  final List<String> favorites = [];
  Map<String, dynamic>? aiStatus;
  final Map<String, String> savedQuery = {};
  final Map<String, String> savedKind = {};
  Timer? _searchTimer;
  String _lastSearch = '';
  String _lastLocation = '';

  Catalog? cat(String gameId) => gameId == 'wilds' ? wilds : world;

  Future<void> boot() async {
    try {
      await vault.open();
      final saved = await vault.get('meta');
      if (saved is String && saved.isNotEmpty) {
        final meta = jsonDecode(saved) as Map<String, dynamic>;
        themeName = meta['theme'] as String? ?? 'light';
        locale = meta['locale'] as String? ?? 'zh-Hans';
        applyDataTheme(themeName);
        offlineReady = meta['offline'] == true;
      }
      final player = await vault.get('player');
      if (player is String && player.isNotEmpty) {
        store.importJson(jsonDecode(player) as Map<String, dynamic>);
      } else if (saved is String && saved.isNotEmpty) {
        final meta = jsonDecode(saved) as Map<String, dynamic>;
        for (final raw in meta['favorites'] as List? ?? const []) {
          final parts = '$raw'.split('|');
          if (parts.length == 3) store.favorite(parts[0], parts[1], parts[2]);
        }
      }
      store.usePartition('visitor');
      _syncFavoriteKeys();
    } catch (e) {
      status = '$e';
    }
    try {
      world = Catalog.decode(utf8.decode((await api.send('GET', '/fixtures/catalog-world.json')).bodyBytes));
      wilds = Catalog.decode(utf8.decode((await api.send('GET', '/fixtures/catalog-wilds.json')).bodyBytes));
    } catch (e) {
      status = '$e';
    }
    try {
      final ent = await entitlement();
      final id = ent?['userId'];
      if (id is String && id.isNotEmpty) {
        userId = id;
        store.usePartition(id);
        await syncBuilds();
        await pullSnapshot();
        await pullPreferences();
      }
    } catch (e) {
      status = '$e';
    }
    _syncFavoriteKeys();
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    await vault.put('meta', jsonEncode({
      'theme': themeName,
      'locale': locale,
      'offline': offlineReady,
      'favorites': favorites,
    }));
  }

  void setTheme(String name) {
    themeName = name == 'dark' ? 'dark' : 'light';
    applyDataTheme(themeName);
    notifyListeners();
    unawaited(persistPreferences());
  }

  void setGame(String id) {
    if (!adoptRouteGame(id) || gameId != id) return;
    notifyListeners();
  }

  bool adoptRouteGame(String? id) {
    if (id != 'world' && id != 'wilds') return false;
    if (gameId == id) return false;
    gameId = id!;
    return true;
  }

  void setLocale(String code) {
    locale = code;
    notifyListeners();
    unawaited(persistPreferences());
  }

  void setProfile(String value) {
    profile = value;
    notifyListeners();
    unawaited(persistPreferences());
  }

  Future<void> persistPreferences() async {
    await _save();
    if (userId == null) return;
    try {
      await api.send('PUT', '/v1/me/preferences', jsonBody: {
        'locale': locale,
        'theme': themeName,
        'contentProfile': profile,
      });
    } catch (_) {}
  }

  Future<void> pullPreferences() async {
    if (userId == null) return;
    try {
      final res = await api.send('GET', '/v1/me/preferences');
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final theme = json['theme'];
      if (theme == 'light' || theme == 'dark') {
        themeName = theme as String;
        applyDataTheme(themeName);
      }
      const locales = ['zh-Hans', 'zh-Hant', 'en', 'ja'];
      final loc = json['locale'];
      if (loc is String && locales.contains(loc)) locale = loc;
      final prof = json['contentProfile'];
      if (prof == 'base' || prof == 'iceborne') profile = prof as String;
    } catch (_) {}
  }

  Future<void> noteInventory(String gameId, String entryId, int quantity, {String kind = 'decoration'}) async {
    store.setInventory(gameId, entryId, quantity, kind: kind);
    await _persistPlayer();
    notifyListeners();
    if (userId != null) await syncBuilds();
  }

  void toggleFavorite(String gameId, String kind, String entryId) {
    if (store.isFavorite(gameId, kind, entryId)) {
      store.unfavorite(gameId, kind, entryId);
    } else {
      store.favorite(gameId, kind, entryId);
    }
    _syncFavoriteKeys();
    notifyListeners();
    _save();
    _persistPlayer();
    if (userId != null) syncBuilds();
  }

  void _syncFavoriteKeys() {
    favorites
      ..clear()
      ..addAll(store.favoriteKeys());
  }

  Future<void> _persistPlayer() async {
    await vault.put('player', jsonEncode(store.exportJson()));
  }

  Future<void> saveLoadout(String gameId, String id, Map<String, dynamic> payload) async {
    store.saveBuild(gameId, id, payload);
    await _persistPlayer();
    notifyListeners();
    if (userId != null) await syncBuilds();
  }

  Future<String> download(String gameId) async {
    final res = await api.send('GET', '/v1/packs/latest?gameId=$gameId&contentProfile=$profile&platformId=pc&patchId=fixture-p1&clientVersion=0.1.0');
    if (res.statusCode != 200) return 'pack ${res.statusCode}';
    final manifest = jsonDecode(res.body) as Map<String, dynamic>;
    final file = await api.send('GET', manifest['url'] as String);
    final result = await PackInstaller().install(
      vault: ContentVault(),
      manifest: manifest,
      body: file.bodyBytes,
      contextKey: gameId,
    );
    if (!result.ok) return result.error ?? 'failed';
    await vault.put('pack-$gameId', file.body);
    offlineReady = world != null && wilds != null;
    await _save();
    notifyListeners();
    return offlineReady ? 'ready' : 'partial';
  }

  Future<SolveResult?> solve(String gameId, SolveRequest request) async {
    final catalog = cat(gameId);
    if (catalog == null) return null;
    final payload = jsonEncode({'request': request.toJson(), 'catalog': catalog.source});
    final raw = await compute(solveJson, payload);
    return SolveResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> login(String user) async {
    final res = await api.send('POST', '/v1/auth/session', jsonBody: {'provider': 'dev', 'userId': user, 'displayName': user});
    if (res.statusCode == 200) {
      userId = user;
      store.usePartition(user);
      notifyListeners();
      await syncBuilds();
      await pullSnapshot();
      await persistPreferences();
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await api.send('DELETE', '/v1/auth/session');
    userId = null;
    store.usePartition('visitor');
    _syncFavoriteKeys();
    await _persistPlayer();
    notifyListeners();
  }

  Future<Map<String, dynamic>?> entitlement() async {
    final res = await api.send('GET', '/v1/me/entitlement');
    if (res.statusCode != 200) return {'code': res.statusCode};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> syncBuilds() async {
    if (userId == null) return 'unauthorized';
    if (store.outbox.isEmpty) return 'empty';
    final ops = store.outbox.map((op) => {
          'opId': op['opId'],
          'recordType': op['recordType'],
          'recordId': op['recordId'],
          'gameId': op['gameId'],
          'kind': op['kind'] ?? '',
          'entryId': op['entryId'] ?? '',
          'baseRevision': op['baseRevision'] ?? 0,
          'action': op['action'],
          'payload': op['payload'],
        }).toList();
    final res = await api.send('POST', '/v1/sync/push', jsonBody: {'ops': ops});
    if (res.statusCode != 200) return res.body;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final applied = <String>{};
    for (final raw in body['results'] as List? ?? const []) {
      if (raw is! Map) continue;
      if (raw['status'] == 'applied') {
        final opId = '${raw['opId']}';
        applied.add(opId);
        store.noteApplied(opId, (raw['revision'] as num?)?.toInt() ?? 0);
      }
    }
    store.outbox.removeWhere((op) => applied.contains(op['opId']));
    await _persistPlayer();
    notifyListeners();
    return res.body;
  }

  Future<void> pullSnapshot() async {
    if (userId == null) return;
    final res = await api.send('GET', '/v1/sync/snapshot');
    if (res.statusCode != 200) return;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final records = <Map<String, dynamic>>[];
    for (final raw in body['records'] as List? ?? const []) {
      if (raw is Map) records.add(Map<String, dynamic>.from(raw));
    }
    store.replaceRemote(records);
    _syncFavoriteKeys();
    await _persistPlayer();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> events(String gameId, {String? q, String? reward}) async {
    final params = <String>['gameId=$gameId'];
    if (q != null && q.isNotEmpty) params.add('q=${Uri.encodeQueryComponent(q)}');
    if (reward != null && reward.isNotEmpty) params.add('reward=${Uri.encodeQueryComponent(reward)}');
    final res = await api.send('GET', '/v1/events?${params.join('&')}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['events'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> event(String id) async {
    final res = await api.send('GET', '/v1/events/$id');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> loadAiStatus() async {
    try {
      final res = await api.send('GET', '/v1/ai/status');
      if (res.statusCode == 200) {
        aiStatus = jsonDecode(res.body) as Map<String, dynamic>;
        notifyListeners();
      }
    } catch (_) {}
  }

  void trackLocation(Uri uri) {
    final signature = uri.toString();
    if (signature == _lastLocation) return;
    _lastLocation = signature;
    final path = uri.path;
    final game = _gameOf(path);
    final kind = _kindOf(path);
    final entry = _entryOf(path);
    final publicId = path.startsWith('/builds/') ? path.split('/').last : '';
    final content = game == 'wilds' ? 'base' : profile;
    unawaited(_collect({
      'type': 'page_view',
      'path': path,
      'gameId': game,
      'contentProfile': content,
      'kind': kind,
      'entryId': entry,
      'publicId': publicId,
    }));
    final q = uri.queryParameters['q'] ?? '';
    if (q.trim().isNotEmpty) {
      unawaited(_collect({
        'type': 'search',
        'path': path,
        'gameId': game,
        'contentProfile': content,
        'query': q,
      }));
    }
    if ((kind == 'weapon' || kind == 'monster') && entry.isNotEmpty) {
      unawaited(_collect({
        'type': 'catalog_view',
        'path': path,
        'gameId': game,
        'contentProfile': content,
        'kind': kind,
        'entryId': entry,
      }));
    }
  }

  void trackSearch(String gameId, String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 500), () {
      final q = query.trim();
      if (q.isEmpty || q == _lastSearch) return;
      _lastSearch = q;
      unawaited(_collect({
        'type': 'search',
        'gameId': gameId,
        'contentProfile': gameId == 'wilds' ? 'base' : profile,
        'query': q,
        'path': '/g/$gameId/entries',
      }));
    });
  }

  Future<void> trackBuild({required String gameId, String weaponId = '', String monsterId = '', List<String> styles = const []}) {
    return _collect({
      'type': 'build_generate',
      'gameId': gameId,
      'contentProfile': gameId == 'wilds' ? 'base' : profile,
      'weaponId': weaponId,
      'monsterId': monsterId,
      'styles': styles,
      'path': '/g/$gameId/builds',
    });
  }

  Future<void> trackShare(String publicId) {
    return _collect({
      'type': 'build_share',
      'publicId': publicId,
      'path': '/builds/$publicId',
    });
  }

  Future<void> recordAiUsage(String gameId, Map<String, dynamic> understood) async {
    List<String> resolve(Object? names, String kind) {
      final catalog = cat(gameId);
      if (catalog == null || names is! List) return const [];
      final out = <String>[];
      for (final name in names) {
        final q = '$name'.trim();
        if (q.isEmpty) continue;
        final hits = catalog.search(profile: gameId == 'wilds' ? 'base' : profile, locale: locale, query: q, kind: kind);
        final exact = hits.where((hit) => hit.entry.entryId == q || hit.entry.displayName(locale, catalog.defaultLocale) == q).toList();
        if (exact.length == 1) out.add(exact.first.entry.entryId);
      }
      return out;
    }

    final weapons = resolve(understood['weaponNames'], 'weapon');
    final monsters = resolve(understood['monsterNames'], 'monster');
    final styles = (understood['styles'] as List? ?? const []).map((item) => '$item'.trim()).where((item) => item.isNotEmpty && item.runes.length <= 16).toList();
    try {
      await api.send('POST', '/v1/ai/usage', jsonBody: {
        'gameId': gameId,
        'contentProfile': gameId == 'wilds' ? 'base' : profile,
        'weaponIds': weapons,
        'monsterIds': monsters,
        'styles': styles,
        'entryIds': [...weapons, ...monsters],
        'inventoryIds': resolve(understood['ownedText'], 'decoration'),
        'excludedIds': resolve(understood['excludeNames'], 'armor'),
        'assumeUnlimitedJewels': understood['assumeUnlimitedJewels'] == true,
        'counted': understood['httpStatus'] == 200,
      });
    } catch (_) {}
  }

  Future<void> _collect(Map<String, dynamic> body) async {
    try {
      await api.send('POST', '/v1/analytics/collect', jsonBody: body);
    } catch (_) {}
  }

  String _gameOf(String path) {
    final parts = path.split('/');
    if (parts.length > 2 && parts[1] == 'g' && (parts[2] == 'world' || parts[2] == 'wilds')) return parts[2];
    return '';
  }

  String _kindOf(String path) {
    final parts = path.split('/');
    if (parts.length > 5 && parts[3] == 'entries') return parts[4];
    return '';
  }

  String _entryOf(String path) {
    final parts = path.split('/');
    if (parts.length > 5 && parts[3] == 'entries') return parts[5];
    return '';
  }

  Future<Map<String, dynamic>> understand(String sentence) async {
    final res = await api.send('POST', '/v1/ai/understand', jsonBody: {'sentence': sentence});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    body['httpStatus'] = res.statusCode;
    return body;
  }

  Future<Map<String, dynamic>> publicBuild(String id) async {
    final res = await api.send('GET', '/v1/public-builds/$id');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    json['httpStatus'] = res.statusCode;
    return json;
  }

  Future<List<Map<String, dynamic>>> hall(String gameId) async {
    final res = await api.send('GET', '/v1/public-builds?gameId=$gameId');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['builds'] as List).cast<Map<String, dynamic>>();
  }
}
