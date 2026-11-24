import 'package:builds/builds.dart';
import 'package:test/test.dart';

void main() {
  test('world defaults are skill level 3 and two jewels', () {
    final seed = seedFor('world');
    expect(seed.targets['fixture-skill-s'], 3);
    expect(seed.jewelCounts['fixture-attack-jewel'], 2);
    expect(seed.fixedIds, containsAll(['fixture-fixed-mail', 'fixture-iron-sword']));
  });

  test('saved loadout keeps weapon, five armor slots, jewels, and tags', () {
    final loadout = Loadout(
      pieces: [
        PlacedPiece('weapon', 'fixture-iron-sword', 'weapon-fixture-iron-sword'),
        PlacedPiece('chest', 'fixture-fixed-mail', 'chest-fixture-fixed-mail'),
      ],
      jewels: [PlacedJewel('fixture-attack-jewel', 'chest-fixture-fixed-mail', 0, 'chest')],
      skills: const {'fixture-skill-s': 3},
      skillSources: const {'fixture-skill-s': ['fixture-fixed-mail']},
      weaponOpen: 0,
      armorOpen: 1,
      stableId: 'stable',
    );
    final payload = persistedLoadout(
      title: '夹具配装',
      fixture: true,
      dataRevision: 'fixture-1',
      tags: const ['夹具'],
      loadout: loadout,
    );
    expect(payload['weapon']['entryId'], 'fixture-iron-sword');
    expect((payload['armor'] as List), hasLength(5));
    expect((payload['armor'] as List)[1]['entryId'], 'fixture-fixed-mail');
    expect((payload['decorations'] as List).single['entryId'], 'fixture-attack-jewel');
    expect(payload['tags'], ['夹具']);
    expect(payload.keys, containsAll(['weapon', 'armor', 'decorations', 'tags']));
  });
}
