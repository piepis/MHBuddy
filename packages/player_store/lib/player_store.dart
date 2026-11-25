import 'dart:convert';

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
    final previous = _box['build:$id'];
    final base = previous?.revision ?? 0;
    transaction(() {
      _box['build:$id'] = StoreRecord(type: 'build', id: id, gameId: gameId, payload: payload, revision: base, sync: queue ? 'pending' : 'local');
      if (queue) {
        outbox.add({
          'opId': 'local-$id-${outbox.length}',
          'recordType': 'build',
          'recordId': id,
          'gameId': gameId,
          'kind': '',
          'entryId': '',
          'baseRevision': base,
          'action': 'upsert',
          'payload': payload,
        });
      }
    });
  }

  void favorite(String gameId, String kind, String entryId) {
    final id = '$kind:$entryId';
    final key = 'favorite:$gameId:$id';
    if (_box.containsKey(key) && _box[key]!.deleted == false && _box[key]!.sync != 'pending-delete') return;
    final base = _box[key]?.revision ?? 0;
    transaction(() {
      _box[key] = StoreRecord(type: 'favorite', id: id, gameId: gameId, payload: {'kind': kind, 'entryId': entryId}, revision: base, sync: 'pending');
      outbox.add({
        'opId': 'local-fav-$gameId-$id-${outbox.length}',
        'recordType': 'favorite',
        'recordId': id,
        'gameId': gameId,
        'kind': kind,
        'entryId': entryId,
        'baseRevision': base,
        'action': 'upsert',
        'payload': {'kind': kind, 'entryId': entryId},
      });
    });
  }

  void unfavorite(String gameId, String kind, String entryId) {
    final id = '$kind:$entryId';
    final key = 'favorite:$gameId:$id';
    final existing = _box[key];
    if (existing == null) return;
    final base = existing.revision;
    transaction(() {
      _box.remove(key);
      outbox.add({
        'opId': 'local-unfav-$gameId-$id-${outbox.length}',
        'recordType': 'favorite',
        'recordId': id,
        'gameId': gameId,
        'kind': kind,
        'entryId': entryId,
        'baseRevision': base,
        'action': 'delete',
        'payload': {'kind': kind, 'entryId': entryId},
      });
    });
  }

  bool isFavorite(String gameId, String kind, String entryId) => _box.containsKey('favorite:$gameId:$kind:$entryId');

  List<String> favoriteKeys() {
    final keys = <String>[];
    for (final record in _box.values) {
      if (record.type != 'favorite' || record.deleted) continue;
      keys.add('${record.gameId}|${record.payload['kind']}|${record.payload['entryId']}');
    }
    return keys;
  }

  void noteApplied(String opId, int revision) {
    Map<String, dynamic>? op;
    for (final item in outbox) {
      if (item['opId'] == opId) op = item;
    }
    if (op == null) return;
    final key = _recordKey('${op['recordType']}', '${op['gameId']}', '${op['recordId']}', '${op['kind'] ?? ''}', '${op['entryId'] ?? ''}');
    for (final box in _partitions.values) {
      final record = box[key];
      if (record == null) continue;
      record.revision = revision;
      record.sync = 'synced';
    }
  }

  void replaceRemote(List<Map<String, dynamic>> records) {
    final pending = <String>{};
    for (final op in outbox) {
      if (op['action'] == 'delete') continue;
      pending.add(_recordKey('${op['recordType']}', '${op['gameId']}', '${op['recordId']}', '${op['kind'] ?? ''}', '${op['entryId'] ?? ''}'));
    }
    final keep = <String, StoreRecord>{};
    for (final entry in _box.entries) {
      if (pending.contains(entry.key)) keep[entry.key] = entry.value;
      else if (entry.value.type != 'build' && entry.value.type != 'favorite' && entry.value.type != 'inventory') keep[entry.key] = entry.value;
    }
    _box
      ..clear()
      ..addAll(keep);
    for (final raw in records) {
      final type = '${raw['recordType']}';
      final id = '${raw['recordId']}';
      final gameId = '${raw['gameId']}';
      final payload = _asMap(raw['payload']);
      final kind = '${raw['kind'] ?? payload['kind'] ?? ''}';
      final entryId = '${raw['entryId'] ?? payload['entryId'] ?? ''}';
      final key = _recordKey(type, gameId, id, kind, entryId);
      if (key.isEmpty || pending.contains(key)) continue;
      final body = payload.isEmpty && type == 'favorite' ? {'kind': kind, 'entryId': entryId} : payload;
      _box[key] = StoreRecord(
        type: type,
        id: id,
        gameId: gameId,
        payload: body,
        revision: (raw['revision'] as num?)?.toInt() ?? 0,
        sync: 'synced',
      );
    }
  }

  Map<String, dynamic> exportJson() {
    final parts = <String, dynamic>{};
    _partitions.forEach((name, box) {
      parts[name] = [
        for (final record in box.values)
          {
            'type': record.type,
            'id': record.id,
            'gameId': record.gameId,
            'payload': record.payload,
            'revision': record.revision,
            'deleted': record.deleted,
            'sync': record.sync,
            'kind': record.payload['kind'],
            'entryId': record.payload['entryId'],
          },
      ];
    });
    return {'partition': partition, 'parts': parts, 'outbox': outbox.map((op) => Map<String, dynamic>.from(op)).toList()};
  }

  void importJson(Map<String, dynamic> json) {
    _partitions.clear();
    outbox.clear();
    final parts = json['parts'];
    if (parts is Map) {
      parts.forEach((name, raw) {
        final box = <String, StoreRecord>{};
        if (raw is List) {
          for (final item in raw) {
            if (item is! Map) continue;
            final record = StoreRecord(
              type: '${item['type']}',
              id: '${item['id']}',
              gameId: '${item['gameId']}',
              payload: item['payload'] is Map ? Map<String, dynamic>.from(item['payload'] as Map) : <String, dynamic>{},
              revision: (item['revision'] as num?)?.toInt() ?? 0,
              deleted: item['deleted'] == true,
              sync: '${item['sync'] ?? 'local'}',
            );
            final key = _recordKey(record.type, record.gameId, record.id, '${item['kind'] ?? record.payload['kind'] ?? ''}', '${item['entryId'] ?? record.payload['entryId'] ?? ''}');
            if (key.isNotEmpty) box[key] = record;
          }
        }
        _partitions['$name'] = box;
      });
    }
    if (_partitions.isEmpty) _partitions['visitor'] = {};
    final part = '${json['partition'] ?? 'visitor'}';
    usePartition(_partitions.containsKey(part) ? part : 'visitor');
    final queued = json['outbox'];
    if (queued is List) {
      for (final op in queued) {
        if (op is Map) outbox.add(Map<String, dynamic>.from(op));
      }
    }
  }

  String _recordKey(String type, String gameId, String id, String kind, String entryId) {
    if (type == 'build') return 'build:$id';
    if (type == 'favorite') return 'favorite:$gameId:$kind:$entryId';
    if (type == 'inventory') return 'inventory:$gameId:$id';
    if (type == 'conflict') return 'conflict:$id';
    return '';
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      final decoded = _tryDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void setInventory(String gameId, String entryId, int quantity, {String kind = 'decoration', bool queue = true}) {
    final key = 'inventory:$gameId:$entryId';
    final base = _box[key]?.revision ?? 0;
    final payload = {'quantity': quantity, 'kind': kind};
    transaction(() {
      outbox.removeWhere((op) => op['recordType'] == 'inventory' && op['gameId'] == gameId && op['recordId'] == entryId && op['action'] == 'upsert');
      _box[key] = StoreRecord(type: 'inventory', id: entryId, gameId: gameId, payload: payload, revision: base, sync: queue ? 'pending' : 'local');
      if (queue) {
        outbox.add({
          'opId': 'local-inv-$gameId-$entryId-${outbox.length}',
          'recordType': 'inventory',
          'recordId': entryId,
          'gameId': gameId,
          'kind': kind,
          'entryId': entryId,
          'baseRevision': base,
          'action': 'upsert',
          'payload': payload,
        });
      }
    });
  }

  int inventoryOf(String gameId, String entryId) => (_box['inventory:$gameId:$entryId']?.payload['quantity'] as int?) ?? 0;

  List<StoreRecord> builds(String gameId) => _box.values.where((r) => r.type == 'build' && r.gameId == gameId && !r.deleted).toList();

  void keepConflict(String id, Map<String, dynamic> local, Map<String, dynamic> server) {
    _box['conflict:$id'] = StoreRecord(type: 'conflict', id: id, gameId: '', payload: {'local': local, 'server': server}, sync: 'conflict');
  }
}
