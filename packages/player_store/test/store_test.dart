import 'package:player_store/player_store.dart';
import 'package:test/test.dart';

void main() {
  test('transaction rolls back the outbox and the record', () {
    final store = PlayerStore();
    store.saveBuild('world', 'b1', {'title': '一'});
    expect(store.builds('world'), hasLength(1));
    expect(store.outbox, hasLength(1));
    expect(() => store.transaction(() => throw StateError('no')), throwsStateError);
    expect(store.builds('world'), hasLength(1));
    expect(store.outbox, hasLength(1));
  });

  test('favorites stay inside the active partition and conflicts are kept', () {
    final store = PlayerStore();
    store.favorite('world', 'material', 'fixture-iron-ore');
    store.favorite('wilds', 'material', 'fixture-wilds-ore');
    expect(store.isFavorite('world', 'material', 'fixture-iron-ore'), isTrue);
    store.usePartition('hunter-a');
    expect(store.isFavorite('world', 'material', 'fixture-iron-ore'), isFalse);
    store.keepConflict('b1', {'title': 'local'}, {'title': 'server'});
    expect(store.builds('world'), isEmpty);
  });

  test('inventory quantity is queued for sync', () {
    final store = PlayerStore();
    store.setInventory('world', 'fixture-attack-jewel', 2);
    store.setInventory('world', 'fixture-charm', 1, kind: 'talisman');
    expect(store.inventoryOf('world', 'fixture-attack-jewel'), 2);
    expect(store.outbox.where((op) => op['recordType'] == 'inventory'), hasLength(2));
    expect(store.outbox.last['payload']['kind'], 'talisman');
  });
}
