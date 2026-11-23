import 'package:idb_shim/idb_client.dart';

import 'factory_stub.dart' if (dart.library.html) 'factory_web.dart';

class Vault {
  Database? _db;

  Future<void> open() async {
    _db = await openFactory().open('mhbuddy', version: 1, onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv');
    });
  }

  Future<void> put(String key, Object value) async {
    final db = _db;
    if (db == null) return;
    final txn = db.transaction('kv', idbModeReadWrite);
    txn.objectStore('kv').put(value, key);
    await txn.completed;
  }

  Future<Object?> get(String key) async {
    final db = _db;
    if (db == null) return null;
    final txn = db.transaction('kv', idbModeReadOnly);
    final value = await txn.objectStore('kv').getObject(key);
    await txn.completed;
    return value;
  }
}
