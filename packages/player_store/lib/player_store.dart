class StoreRecord {
  StoreRecord({required this.type, required this.id, required this.gameId, required this.payload, this.revision = 0, this.deleted = false, this.sync = 'local'});
  final String type;
  final String id;
  final String gameId;
  Map<String, dynamic> payload;
  int revision;
  bool deleted;
  String sync;
}

class PlayerStore {
  final Map<String, Map<String, StoreRecord>> _partitions = {'visitor': {}};
  String partition = 'visitor';
  final List<Map<String, dynamic>> outbox = [];

  void usePartition(String name) {
    partition = name;
    _partitions.putIfAbsent(name, () => {});
  }

  Map<String, StoreRecord> get _box => _partitions[partition]!;

  void transaction(void Function() body) {
    final snap = _box.map((k, v) => MapEntry(k, StoreRecord(type: v.type, id: v.id, gameId: v.gameId, payload: Map<String, dynamic>.from(v.payload), revision: v.revision, deleted: v.deleted, sync: v.sync)));
    final outSnap = outbox.map((e) => Map<String, dynamic>.from(e)).toList();
    try {
      body();
    } catch (e) {
      _partitions[partition] = snap;
      outbox
        ..clear()
        ..addAll(outSnap);
      rethrow;
    }
  }

  void saveBuild(String gameId, String id, Map<String, dynamic> payload, {bool queue = true}) {
    transaction(() {
      _box['build:$id'] = StoreRecord(type: 'build', id: id, gameId: gameId, payload: payload, sync: queue ? 'pending' : 'local');
      if (queue) {
        outbox.add({'opId': 'local-$id-${outbox.length}', 'recordType': 'build', 'recordId': id, 'gameId': gameId, 'action': 'upsert', 'payload': payload});
      }
    });
  }

  void favorite(String gameId, String kind, String entryId) {
    final id = '$kind:$entryId';
    transaction(() {
      _box['favorite:$gameId:$id'] = StoreRecord(type: 'favorite', id: id, gameId: gameId, payload: {'kind': kind, 'entryId': entryId}, sync: 'local');
    });
  }

  bool isFavorite(String gameId, String kind, String entryId) => _box.containsKey('favorite:$gameId:$kind:$entryId');

  void setInventory(String gameId, String entryId, int quantity) {
    _box['inventory:$gameId:$entryId'] = StoreRecord(type: 'inventory', id: entryId, gameId: gameId, payload: {'quantity': quantity}, sync: 'local');
  }

  int inventoryOf(String gameId, String entryId) => (_box['inventory:$gameId:$entryId']?.payload['quantity'] as int?) ?? 0;

  List<StoreRecord> builds(String gameId) => _box.values.where((r) => r.type == 'build' && r.gameId == gameId && !r.deleted).toList();

  void keepConflict(String id, Map<String, dynamic> local, Map<String, dynamic> server) {
    _box['conflict:$id'] = StoreRecord(type: 'conflict', id: id, gameId: '', payload: {'local': local, 'server': server}, sync: 'conflict');
  }
}
