import 'dart:convert';
import 'dart:io';

import 'package:builds/builds.dart';
import 'package:catalog/catalog.dart';
import 'package:test/test.dart';

Catalog load(String name) => Catalog.decode(File('../../content/fixtures/$name').readAsStringSync());

void main() {
  late Catalog world;
  late Catalog wilds;

  setUpAll(() {
    world = load('catalog-world.json');
    wilds = load('catalog-wilds.json');
  });

  SolveResult run(Catalog cat, {required int jewels, required bool useInventory, List<String> excluded = const [], List<ReservedSlot> reserved = const [], String game = 'world', Map<String, int>? target, List<String> fixed = const ['fixture-fixed-mail'], Duration? budget}) {
    return solve(
      SolveRequest(
        gameId: game,
        contentProfile: 'base',
        targetSkills: target ?? {'fixture-skill-s': 3},
        fixedEquipment: fixed,
        excludedEquipment: excluded,
        useInventory: useInventory,
        inventory: {'fixture-attack-jewel': jewels},
        timeBudget: budget ?? const Duration(seconds: 2),
        reserved: reserved,
      ),
      cat,
    );
  }

  test('inventory on solves only with two slots and two jewels', () {
    final both = run(world, jewels: 2, useInventory: true);
    expect(both.searchComplete, isTrue);
    expect(both.loadouts, isNotEmpty);
    expect(both.loadouts.first.skills['fixture-skill-s'], greaterThanOrEqualTo(3));
    expect(run(world, jewels: 1, useInventory: true).loadouts, isEmpty);
    expect(run(world, jewels: 2, useInventory: true, excluded: ['fixture-waist-slot']).loadouts, isEmpty);
    expect(run(world, jewels: 1, useInventory: false).loadouts, isNotEmpty);
  });

  test('fixed and excluded overlap is a field error', () {
    final result = run(world, jewels: 2, useInventory: false, excluded: ['fixture-fixed-mail']);
    expect(result.fieldErrors, isNotEmpty);
    expect(result.loadouts, isEmpty);
  });

  test('world rejects reserved slots and a zero budget stops', () {
    final reserved = run(world, jewels: 2, useInventory: false, reserved: [ReservedSlot(part: 'weapon', index: 0)]);
    expect(reserved.fieldErrors, contains('reserved_unsupported'));
    final timed = run(world, jewels: 2, useInventory: false, budget: Duration.zero);
    expect(timed.searchComplete, isFalse);
    expect(timed.stopReason, 'time');
  });

  test('wilds keeps a reserved weapon slot empty', () {
    final result = solve(
      SolveRequest(
        gameId: 'wilds',
        contentProfile: 'base',
        targetSkills: {'fixture-skill-y': 1},
        fixedEquipment: const ['fixture-weapon-w', 'fixture-head-h'],
        useInventory: false,
        reserved: [ReservedSlot(part: 'weapon', index: 0)],
      ),
      wilds,
    );
    expect(result.searchComplete, isTrue, reason: result.stopReason);
    expect(result.loadouts, isNotEmpty);
    final hit = result.loadouts.first;
    expect(hit.weaponOpen, greaterThanOrEqualTo(1));
    expect(hit.jewels.map((j) => j.entryId), contains('fixture-jewel-k'));
    expect(hit.jewels.where((j) => j.part == 'weapon'), isEmpty);
    expect(hit.skillSources['fixture-skill-y'], contains('fixture-jewel-k'));
    final blocked = solve(
      SolveRequest(
        gameId: 'wilds',
        contentProfile: 'base',
        targetSkills: {'fixture-skill-x': 1},
        fixedEquipment: const ['fixture-weapon-w'],
        useInventory: false,
        reserved: [ReservedSlot(part: 'weapon', index: 0)],
      ),
      wilds,
    );
    expect(blocked.loadouts.where((l) => l.jewels.any((j) => j.part == 'weapon')), isEmpty);
  });

  test('equipped fixture round trip and swapped sockets', () {
    final file = jsonDecode(File('../../contracts/examples/wilds-build-equipped.fixture.json').readAsStringSync()) as Map<String, dynamic>;
    final again = roundTripBuild(file);
    expect(again['weapon']['entryId'], 'fixture-weapon-w');
    expect((again['decorations'] as List).length, 2);
    final preview = previewBuild(file, wilds);
    expect(preview.ok, isTrue, reason: preview.error);
    expect(preview.sources['fixture-skill-x'], ['fixture-jewel-j']);
    expect(preview.sources['fixture-skill-y'], ['fixture-jewel-k']);
    final swapped = jsonDecode(jsonEncode(file)) as Map<String, dynamic>;
    final decos = swapped['decorations'] as List;
    final first = Map<String, dynamic>.from(decos[0] as Map);
    final second = Map<String, dynamic>.from(decos[1] as Map);
    decos[0] = {...first, 'entryId': second['entryId']};
    decos[1] = {...second, 'entryId': first['entryId']};
    final bad = previewBuild(swapped, wilds);
    expect(bad.ok, isFalse);
    expect(bad.error, contains('slot_type'));
    final draft = jsonDecode(File('../../contracts/examples/wilds-build-v1.fixture.json').readAsStringSync()) as Map<String, dynamic>;
    expect(previewBuild(draft, wilds).error, contains('missing_ref'));
    expect(previewBuild(file, world).error, 'cross_game');
  });
}
