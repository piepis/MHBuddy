import 'dart:convert';

import 'package:catalog/catalog.dart';

class BuildPreview {
  BuildPreview({required this.ok, this.error, this.skills = const {}, this.sources = const {}});
  final bool ok;
  final String? error;
  final Map<String, int> skills;
  final Map<String, List<String>> sources;
}

BuildPreview previewBuild(Map<String, dynamic> file, Catalog catalog) {
  if (file['format'] != 'mhbuddy.build') {
    return BuildPreview(ok: false, error: 'bad_format');
  }
  if (file['gameId'] != catalog.gameId) {
    return BuildPreview(ok: false, error: 'cross_game');
  }
  final weapon = file['weapon'];
  if (weapon is! Map) return BuildPreview(ok: false, error: 'bad_weapon');
  final weaponId = weapon['entryId'] as String?;
  final weaponEntry = weaponId == null ? null : catalog.byId(weaponId);
  if (weaponEntry == null || weaponEntry.kind != 'weapon') {
    return BuildPreview(ok: false, error: 'missing_ref:$weaponId');
  }
  final instances = <String, CatalogEntry>{};
  final weaponInstance = (weapon['instanceId'] as String?) ?? 'weapon';
  instances[weaponInstance] = weaponEntry;
  final armor = file['armor'];
  if (armor is! List) return BuildPreview(ok: false, error: 'bad_armor');
  for (final raw in armor) {
    if (raw is! Map) return BuildPreview(ok: false, error: 'bad_armor');
    final id = raw['entryId'] as String?;
    final entry = id == null ? null : catalog.byId(id);
    if (id == null || entry == null) return BuildPreview(ok: false, error: 'missing_ref:$id');
    final instance = (raw['instanceId'] as String?) ?? id;
    instances[instance] = entry;
  }
  final decorations = file['decorations'];
  if (decorations is! List) return BuildPreview(ok: false, error: 'bad_decorations');
  final skills = <String, int>{};
  final sources = <String, List<String>>{};
  void addSkills(CatalogEntry entry, String source) {
    for (final g in entry.skills) {
      skills[g.skillId] = (skills[g.skillId] ?? 0) + g.level;
      sources.putIfAbsent(g.skillId, () => []).add(source);
    }
  }
  for (final entry in instances.values) {
    addSkills(entry, entry.entryId);
  }
  for (final raw in decorations) {
    if (raw is! Map) return BuildPreview(ok: false, error: 'bad_decorations');
    final id = raw['entryId'] as String?;
    final jewel = id == null ? null : catalog.byId(id);
    if (jewel == null || jewel.kind != 'decoration') {
      return BuildPreview(ok: false, error: 'missing_ref:$id');
    }
    final hostId = raw['equipInstanceId'] as String?;
    final host = hostId == null ? null : instances[hostId];
    if (host == null) return BuildPreview(ok: false, error: 'missing_host:$hostId');
    final index = (raw['slotIndex'] as num?)?.toInt();
    if (index == null) return BuildPreview(ok: false, error: 'bad_slot');
    final slot = host.slots.where((s) => s.index == index).toList();
    if (slot.isEmpty || slot.single.accept != jewel.slotType) {
      return BuildPreview(ok: false, error: 'slot_type:$id@$index');
    }
    addSkills(jewel, jewel.entryId);
  }
  return BuildPreview(ok: true, skills: skills, sources: sources);
}

Map<String, dynamic> roundTripBuild(Map<String, dynamic> file) =>
    jsonDecode(jsonEncode(file)) as Map<String, dynamic>;
