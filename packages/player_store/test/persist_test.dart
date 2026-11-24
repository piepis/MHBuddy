import 'package:player_store/player_store.dart';
import 'package:test/test.dart';

void main() {
  test('unfavorite removes the mark and queues a delete', () {
    final store = PlayerStore();
    store.favorite('world', 'material', 'fixture-rare-ore');
    expect(store.isFavorite('world', 'material', 'fixture-rare-ore'), isTrue);
    store.unfavorite('world', 'material', 'fixture-rare-ore');
    expect(store.isFavorite('world', 'material', 'fixture-rare-ore'), isFalse);
    expect(store.outbox.last['action'], 'delete');
    expect(store.favoriteKeys(), isEmpty);
  });

  test('a second save keeps the server revision as baseRevision', () {
    final store = PlayerStore();
    store.saveBuild('world', 'b1', {
      'title': '夹具配装',
      'weapon': {'entryId': 'fixture-iron-sword'},
      'armor': [
        {'slot': 'head'},
        {'slot': 'chest', 'entryId': 'fixture-fixed-mail'},
        {'slot': 'arms'},
        {'slot': 'waist'},
        {'slot': 'legs'},
      ],
      'decorations': [
        {'part': 'chest', 'slotIndex': 0, 'entryId': 'fixture-attack-jewel'},
      ],
      'tags': ['夹具'],
    });
    expect(store.outbox.single['baseRevision'], 0);
    expect(store.outbox.single['payload']['weapon']['entryId'], 'fixture-iron-sword');
    store.noteApplied(store.outbox.single['opId'] as String, 1);
    store.outbox.clear();
    store.saveBuild('world', 'b1', {'title': '夹具配装', 'weapon': {'entryId': 'fixture-iron-sword'}});
    expect(store.outbox.single['baseRevision'], 1);
  });

  test('export and import keep the build and the outbox', () {
    final store = PlayerStore();
    store.saveBuild('wilds', 'copy-1', {'title': '夹具公开配装', 'weapon': {'entryId': 'fixture-weapon-w'}});
    final again = PlayerStore();
    again.importJson(store.exportJson());
    expect(again.builds('wilds').single.payload['weapon']['entryId'], 'fixture-weapon-w');
    expect(again.outbox.single['recordId'], 'copy-1');
  });

  test('snapshot replaces the partition with the server build', () {
    final store = PlayerStore();
    store.usePartition('hunter-a');
    store.replaceRemote([
      {
        'gameId': 'world',
        'recordType': 'build',
        'recordId': 'local-1',
        'revision': 2,
        'payload': {
          'title': '夹具配装',
          'weapon': {'entryId': 'fixture-iron-sword'},
          'decorations': [
            {'entryId': 'fixture-attack-jewel', 'slotIndex': 0},
          ],
        },
      },
    ]);
    expect(store.builds('world').single.revision, 2);
    expect(store.builds('world').single.payload['decorations'][0]['entryId'], 'fixture-attack-jewel');
  });
}
