import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:catalog/catalog.dart';
import 'package:test/test.dart';

Catalog load(String name) => Catalog.decode(File('../../content/fixtures/$name').readAsStringSync());

Map<String, dynamic> loadMap(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Catalog world;
  late Catalog wilds;

  setUpAll(() {
    world = load('catalog-world.json');
    wilds = load('catalog-wilds.json');
  });

  test('search aliases, case, width, and locale fallback', () {
    final zh = world.search(profile: 'base', locale: 'zh-Hans', query: '豺龙');
    expect(zh.map((h) => h.entry.entryId), contains('fixture-jagras'));
    final en = world.search(profile: 'base', locale: 'en', query: 'JAGRAS');
    expect(en.single.entry.entryId, 'fixture-jagras');
    final wide = world.search(profile: 'base', locale: 'en', query: 'ＪＡＧＲＡＳ');
    expect(wide, isNotEmpty);
    final ja = world.search(profile: 'base', locale: 'ja', query: 'ジャグラス');
    expect(ja.single.entry.displayName('ja', 'zh-Hans'), 'フィクスチャジャグラス');
    final ko = world.search(profile: 'base', locale: 'ko');
    expect(ko.first.fallbackLocale, 'zh-Hans');
  });

  test('base profile hides iceborne-only entries', () {
    expect(world.search(profile: 'base', locale: 'zh-Hans', query: '冰原'), isEmpty);
    expect(world.search(profile: 'iceborne', locale: 'zh-Hans', query: '冰原古龙'), isNotEmpty);
  });

  test('same fixture name is a different entry per game', () {
    final a = world.search(profile: 'base', locale: 'zh-Hans', query: '夹具铁矿').single;
    final b = wilds.search(profile: 'base', locale: 'zh-Hans', query: '夹具铁矿').single;
    expect(a.entry.displayName('zh-Hans', 'zh-Hans'), b.entry.displayName('zh-Hans', 'zh-Hans'));
    expect(a.entry.entryId, isNot(b.entry.entryId));
  });

  test('map deep link waits until the catalog exists, then opens the rare node', () {
    expect(tuneMap(null, 'fixture-rare-ore').ready, isFalse);
    final tuned = tuneMap(world, 'fixture-rare-ore');
    expect(tuned.ready, isTrue);
    expect(tuned.layerId, 'floor-2');
    expect(tuned.resourceId, 'fixture-rare-ore');
    expect(tuned.conditions, '夹具：可能出现');
  });

  test('relations and map layers', () {
    expect(world.fromEntry('monster', 'fixture-jagras').map((r) => r.toId), contains('fixture-iron-ore'));
    expect(wilds.fromEntry('weapon', 'fixture-weapon-w').single.toId, 'fixture-weapon-child');
    expect(wilds.fromEntry('weapon', 'fixture-weapon-child').single.toId, 'fixture-wilds-ore');
    expect(wilds.toEntry('skill', 'fixture-skill-x').single.fromId, 'fixture-jewel-j');
    final floor1 = world.pois(mapId: 'fixture-ancient-forest', layerId: 'floor-1');
    final floor2 = world.pois(mapId: 'fixture-ancient-forest', layerId: 'floor-2');
    expect(floor1.single.resourceId, 'fixture-iron-ore');
    expect(floor2.single.resourceId, 'fixture-rare-ore');
    expect(floor1.single.xNorm, floor2.single.xNorm);
    expect(floor1.single.layerId, isNot(floor2.single.layerId));
  });

  test('pack install rejects bad hash, bad signature, quota, and stale revision', () async {
    final body = File('../../content/fixtures/catalog-world.json').readAsBytesSync();
    final manifest = loadMap('../../content/fixtures/manifests/world.json');
    final installer = PackInstaller();
    final ok = await installer.install(vault: ContentVault(), manifest: manifest, body: body, contextKey: 'world');
    expect(ok.ok, isTrue);
    expect(ok.activeRevision, 'fixture-1');

    final flipped = Uint8List.fromList(body);
    flipped[0] ^= 0xff;
    final badHash = await installer.install(vault: ContentVault(), manifest: manifest, body: flipped, contextKey: 'world');
    expect(badHash.error, 'HASH_MISMATCH');

    final badSig = Map<String, dynamic>.from(manifest)..['signature'] = 'AAAA';
    final sig = await installer.install(vault: ContentVault(), manifest: badSig, body: body, contextKey: 'world');
    expect(sig.ok, isFalse);

    final quota = await installer.install(vault: ContentVault(quotaBytes: 8), manifest: manifest, body: body, contextKey: 'world');
    expect(quota.error, 'QUOTA');

    final newer = Map<String, dynamic>.from(manifest)
      ..['revisionNumber'] = 2
      ..['dataRevision'] = 'fixture-2';
    final vault2 = ContentVault();
    await installer.install(vault: vault2, manifest: newer, body: body, contextKey: 'world');
    final stale = await installer.install(vault: vault2, manifest: manifest, body: body, contextKey: 'world');
    expect(stale.activeRevision, 'fixture-2');
    expect(stale.error, 'KEPT_NEWER');

    final diff = Map<String, dynamic>.from(newer)..['diff'] = {'parent': 'missing-baseline'};
    final full = await installer.install(vault: ContentVault(), manifest: diff, body: body, contextKey: 'world');
    expect(full.ok, isTrue);
    expect(full.usedFullPack, isTrue);
  });

  test('10k name scan stays under the local budget', () {
    final entries = List.generate(10000, (i) {
      return {
        'kind': 'item',
        'entryId': 'n-$i',
        'texts': {
          'zh-Hans': {'name': '条目$i 别名${i % 17}', 'aliases': ['a$i'], 'summary': '夹具'},
        },
      };
    });
    final cat = Catalog.fromJson({
      'gameId': 'world',
      'dataRevision': 'fixture-bench',
      'revisionNumber': 1,
      'rulesetVersion': 'fixture-r1',
      'patchId': 'fixture-p1',
      'defaultLocale': 'zh-Hans',
      'fixture': true,
      'entries': entries,
      'relations': [],
      'maps': [],
    });
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      cat.search(profile: 'base', locale: 'zh-Hans', query: '条目${i * 97}');
    }
    sw.stop();
    expect(sw.elapsedMilliseconds < 2000, isTrue, reason: '100 scans took ${sw.elapsedMilliseconds}ms');
  });
}
