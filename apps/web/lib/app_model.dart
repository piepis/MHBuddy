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
        for (final raw in meta['favorites'] as List? ?? const []) {
          final key = '$raw';
          favorites.add(key);
          final p = key.split('|');
          if (p.length == 3) store.favorite(p[0], p[1], p[2]);
        }
      }
    } catch (e) {
      status = '$e';
    }
    try {
      world = Catalog.decode(utf8.decode((await api.send('GET', '/fixtures/catalog-world.json')).bodyBytes));
      wilds = Catalog.decode(utf8.decode((await api.send('GET', '/fixtures/catalog-wilds.json')).bodyBytes));
    } catch (e) {
      status = '$e';
    }
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
    _save();
  }

  void setGame(String id) {
    if (id != 'world' && id != 'wilds') return;
    gameId = id;
    notifyListeners();
  }

  void setLocale(String code) {
    locale = code;
    notifyListeners();
    _save();
  }

  void setProfile(String value) {
    profile = value;
    notifyListeners();
  }

  void toggleFavorite(String gameId, String kind, String entryId) {
    final key = '$gameId|$kind|$entryId';
    if (favorites.contains(key)) return;
    favorites.add(key);
    store.favorite(gameId, kind, entryId);
    notifyListeners();
    _save();
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
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await api.send('DELETE', '/v1/auth/session');
    userId = null;
    store.usePartition('visitor');
    notifyListeners();
  }

  Future<Map<String, dynamic>?> entitlement() async {
    final res = await api.send('GET', '/v1/me/entitlement');
    if (res.statusCode != 200) return {'code': res.statusCode};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> syncBuilds() async {
    if (store.outbox.isEmpty) return 'empty';
    final ops = store.outbox.map((op) => {
          'opId': op['opId'],
          'recordType': op['recordType'],
          'recordId': op['recordId'],
          'gameId': op['gameId'],
          'baseRevision': 0,
          'action': op['action'],
          'payload': op['payload'],
        }).toList();
    final res = await api.send('POST', '/v1/sync/push', jsonBody: {'ops': ops});
    return res.body;
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
