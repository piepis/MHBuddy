import 'dart:io';

import 'package:builds/builds.dart';
import 'package:catalog/catalog.dart';
import 'package:test/test.dart';

void main() {
  final world = Catalog.decode(File('../../content/fixtures/catalog-world.json').readAsStringSync());

  test('template numbers come from the solver and gaps use relations', () {
    final result = solve(
      SolveRequest(
        gameId: 'world',
        contentProfile: 'base',
        targetSkills: const {'fixture-skill-s': 3},
        fixedEquipment: const ['fixture-fixed-mail', 'fixture-iron-sword'],
        useInventory: false,
      ),
      world,
    );
    final text = explainLoadout(result: result, catalog: world, assumeUnlimited: true, dataRevision: world.dataRevision, fixture: true);
    expect(text.fixtureLine, contains('不是游戏实数'));
    expect(text.skillLines.join(' '), contains('3'));
    expect(text.gaps.any((g) => g.entryId == 'fixture-iron-ore' && g.checked && g.monsterId == 'fixture-jagras'), isTrue);
  });

  test('unknown style is not invented as a skill', () {
    final unsupported = <String>[];
    final targets = targetsForStyles(const ['会心'], unsupported);
    expect(targets, isEmpty);
    expect(unsupported, ['会心']);
  });
}