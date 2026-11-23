import 'solver.dart';

const armorSlots = ['head', 'chest', 'arms', 'waist', 'legs'];

Map<String, dynamic> persistedLoadout({
  required String title,
  required bool fixture,
  required String dataRevision,
  required List<String> tags,
  Loadout? loadout,
}) {
  String? weaponId;
  String? weaponInstance;
  final armorIds = {for (final slot in armorSlots) slot: null as String?};
  for (final piece in loadout?.pieces ?? const <PlacedPiece>[]) {
    if (piece.part == 'weapon') {
      weaponId = piece.entryId;
      weaponInstance = piece.instanceId;
    } else if (armorIds.containsKey(piece.part)) {
      armorIds[piece.part] = piece.entryId;
    }
  }
  return {
    'title': title,
    'fixture': fixture,
    'dataRevision': dataRevision,
    'tags': tags,
    'weapon': weaponId == null ? null : {'entryId': weaponId, 'instanceId': weaponInstance},
    'armor': [
      for (final slot in armorSlots) {'slot': slot, 'entryId': armorIds[slot]},
    ],
    'decorations': [
      for (final jewel in loadout?.jewels ?? const <PlacedJewel>[])
        {
          'entryId': jewel.entryId,
          'equipInstanceId': jewel.equipInstanceId,
          'slotIndex': jewel.slotIndex,
          'part': jewel.part,
        },
    ],
  };
}

Map<String, dynamic> persistedPublic(Map<String, dynamic> snapshot, {required String sourceId}) {
  return {
    'title': snapshot['title'] ?? sourceId,
    'fixture': true,
    'dataRevision': snapshot['dataRevision'],
    'tags': snapshot['tags'] ?? const <String>[],
    'weapon': snapshot['weapon'],
    'armor': snapshot['armor'],
    'decorations': snapshot['decorations'],
    'source': sourceId,
  };
}
