import 'dart:convert';

import 'package:catalog/catalog.dart';

class ReservedSlot {
  ReservedSlot({required this.part, required this.index});
  final String part;
  final int index;

  Map<String, dynamic> toJson() => {'part': part, 'index': index};
  static ReservedSlot fromJson(Map<String, dynamic> json) =>
      ReservedSlot(part: json['part'] as String, index: (json['index'] as num).toInt());
}

class SolveRequest {
  SolveRequest({
    required this.gameId,
    required this.contentProfile,
    required this.targetSkills,
    this.fixedEquipment = const [],
    this.excludedEquipment = const [],
    this.useInventory = false,
    this.inventory = const {},
    this.topK = 20,
    this.timeBudget = const Duration(seconds: 2),
    this.reserved = const [],
  });

  final String gameId;
  final String contentProfile;
  final Map<String, int> targetSkills;
  final List<String> fixedEquipment;
  final List<String> excludedEquipment;
  final bool useInventory;
  final Map<String, int> inventory;
  final int topK;
  final Duration timeBudget;
  final List<ReservedSlot> reserved;

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'contentProfile': contentProfile,
        'targetSkills': targetSkills,
        'fixedEquipment': fixedEquipment,
        'excludedEquipment': excludedEquipment,
        'useInventory': useInventory,
        'inventory': inventory,
        'topK': topK,
        'timeBudgetMs': timeBudget.inMilliseconds,
        'reserved': reserved.map((e) => e.toJson()).toList(),
      };

  static SolveRequest fromJson(Map<String, dynamic> json) => SolveRequest(
        gameId: json['gameId'] as String,
        contentProfile: json['contentProfile'] as String,
        targetSkills: (json['targetSkills'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
        fixedEquipment: (json['fixedEquipment'] as List? ?? const []).map((e) => '$e').toList(),
        excludedEquipment: (json['excludedEquipment'] as List? ?? const []).map((e) => '$e').toList(),
        useInventory: json['useInventory'] == true,
        inventory: (json['inventory'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt())),
        topK: (json['topK'] as num?)?.toInt() ?? 20,
        timeBudget: Duration(milliseconds: (json['timeBudgetMs'] as num?)?.toInt() ?? 2000),
        reserved: (json['reserved'] as List? ?? const []).map((e) => ReservedSlot.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class PlacedPiece {
  PlacedPiece(this.part, this.entryId, this.instanceId);
  final String part;
  final String entryId;
  final String instanceId;
}

class PlacedJewel {
  PlacedJewel(this.entryId, this.equipInstanceId, this.slotIndex, this.part);
  final String entryId;
  final String equipInstanceId;
  final int slotIndex;
  final String part;
}

class Loadout {
  Loadout({
    required this.pieces,
    required this.jewels,
    required this.skills,
    required this.skillSources,
    required this.weaponOpen,
    required this.armorOpen,
    required this.stableId,
  });
  final List<PlacedPiece> pieces;
  final List<PlacedJewel> jewels;
  final Map<String, int> skills;
  final Map<String, List<String>> skillSources;
  final int weaponOpen;
  final int armorOpen;
  final String stableId;

  int get openSlots => weaponOpen + armorOpen;

  Map<String, dynamic> toJson() => {
        'pieces': pieces.map((p) => {'part': p.part, 'entryId': p.entryId, 'instanceId': p.instanceId}).toList(),
        'jewels': jewels
            .map((j) => {'entryId': j.entryId, 'equipInstanceId': j.equipInstanceId, 'slotIndex': j.slotIndex, 'part': j.part})
            .toList(),
        'skills': skills,
        'skillSources': skillSources,
        'weaponOpen': weaponOpen,
        'armorOpen': armorOpen,
        'stableId': stableId,
      };
}

class SolveResult {
  SolveResult({
    required this.loadouts,
    required this.searchComplete,
    required this.stopReason,
    this.fieldErrors = const [],
  });
  final List<Loadout> loadouts;
  final bool searchComplete;
  final String stopReason;
  final List<String> fieldErrors;

  Map<String, dynamic> toJson() => {
        'loadouts': loadouts.map((e) => e.toJson()).toList(),
        'searchComplete': searchComplete,
        'stopReason': stopReason,
        'fieldErrors': fieldErrors,
      };

  static SolveResult fromJson(Map<String, dynamic> json) => SolveResult(
        loadouts: (json['loadouts'] as List).map((raw) {
          final m = raw as Map<String, dynamic>;
          return Loadout(
            pieces: (m['pieces'] as List)
                .map((p) => PlacedPiece(p['part'] as String, p['entryId'] as String, p['instanceId'] as String))
                .toList(),
            jewels: (m['jewels'] as List)
                .map((p) => PlacedJewel(p['entryId'] as String, p['equipInstanceId'] as String, (p['slotIndex'] as num).toInt(), p['part'] as String))
                .toList(),
            skills: (m['skills'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
            skillSources: (m['skillSources'] as Map).map((k, v) => MapEntry('$k', (v as List).map((e) => '$e').toList())),
            weaponOpen: (m['weaponOpen'] as num).toInt(),
            armorOpen: (m['armorOpen'] as num).toInt(),
            stableId: m['stableId'] as String,
          );
        }).toList(),
        searchComplete: json['searchComplete'] == true,
        stopReason: json['stopReason'] as String,
        fieldErrors: (json['fieldErrors'] as List? ?? const []).map((e) => '$e').toList(),
      );
}

const armorParts = ['weapon', 'head', 'chest', 'arms', 'waist', 'legs'];

SolveResult solve(SolveRequest request, Catalog catalog) {
  if (request.gameId == 'world' && request.reserved.isNotEmpty) {
    return SolveResult(loadouts: const [], searchComplete: true, stopReason: 'field', fieldErrors: const ['reserved_unsupported']);
  }
  final overlap = request.fixedEquipment.toSet().intersection(request.excludedEquipment.toSet());
  if (overlap.isNotEmpty) {
    return SolveResult(loadouts: const [], searchComplete: true, stopReason: 'field', fieldErrors: ['fixed_excluded:${overlap.join(',')}']);
  }
  final deadline = DateTime.now().add(request.timeBudget);
  if (!deadline.isAfter(DateTime.now())) {
    return SolveResult(loadouts: const [], searchComplete: false, stopReason: 'time');
  }
  final byPart = <String, List<CatalogEntry>>{};
  for (final part in armorParts) {
    byPart[part] = [];
  }
  for (final e in catalog.entries) {
    if (e.part == null || !armorParts.contains(e.part)) continue;
    if (!catalog.profileAllows(e, request.contentProfile)) continue;
    if (request.excludedEquipment.contains(e.entryId)) continue;
    byPart[e.part]!.add(e);
  }
  for (final id in request.fixedEquipment) {
    final e = catalog.byId(id);
    if (e == null || e.part == null) {
      return SolveResult(loadouts: const [], searchComplete: true, stopReason: 'field', fieldErrors: ['unknown_fixed:$id']);
    }
    byPart[e.part!] = [e];
  }
  final jewels = catalog.entries.where((e) => e.kind == 'decoration').toList();
  final found = <Loadout>[];
  var complete = true;

  void walk(int partIndex, List<CatalogEntry> chosen) {
    if (!complete) return;
    if (!DateTime.now().isBefore(deadline)) {
      complete = false;
      return;
    }
    if (partIndex == armorParts.length) {
      final upper = _upper(chosen, jewels, request);
      if (!_meetsUpper(upper, request.targetSkills)) return;
      _assignJewels(request, chosen, jewels, found);
      return;
    }
    final part = armorParts[partIndex];
    final options = byPart[part]!;
    final fixedHere = options.length == 1 && request.fixedEquipment.contains(options.single.entryId);
    if (!fixedHere) {
      walk(partIndex + 1, chosen);
    }
    for (final piece in options) {
      walk(partIndex + 1, [...chosen, piece]);
    }
  }

  walk(0, []);
  found.sort((a, b) {
    final open = b.openSlots.compareTo(a.openSlots);
    if (open != 0) return open;
    return a.stableId.compareTo(b.stableId);
  });
  final kept = found.length > request.topK ? found.sublist(0, request.topK) : found;
  return SolveResult(
    loadouts: kept,
    searchComplete: complete,
    stopReason: complete ? 'complete' : 'time',
  );
}

Map<String, int> _upper(List<CatalogEntry> pieces, List<CatalogEntry> jewels, SolveRequest request) {
  final skills = <String, int>{};
  var slots = 0;
  for (final p in pieces) {
    for (final s in p.skills) {
      skills[s.skillId] = (skills[s.skillId] ?? 0) + s.level;
    }
    for (final slot in p.slots) {
      final reserved = request.reserved.any((r) => r.part == p.part && r.index == slot.index);
      if (!reserved) slots++;
    }
  }
  var best = 0;
  for (final j in jewels) {
    for (final s in j.skills) {
      if (s.level > best) best = s.level;
    }
  }
  if (best == 0) best = 1;
  for (final skill in request.targetSkills.keys) {
    skills[skill] = (skills[skill] ?? 0) + slots * best;
  }
  return skills;
}

bool _meetsUpper(Map<String, int> upper, Map<String, int> target) {
  for (final e in target.entries) {
    if ((upper[e.key] ?? 0) < e.value) return false;
  }
  return true;
}

void _assignJewels(SolveRequest request, List<CatalogEntry> pieces, List<CatalogEntry> jewels, List<Loadout> found) {
  final open = <({String part, String instanceId, int index, String accept})>[];
  var reservedWeapon = 0;
  var reservedArmor = 0;
  for (final p in pieces) {
    final instance = '${p.part}-${p.entryId}';
    for (final slot in p.slots) {
      final reserved = request.reserved.any((r) => r.part == p.part && r.index == slot.index);
      if (reserved) {
        if (p.part == 'weapon') {
          reservedWeapon++;
        } else {
          reservedArmor++;
        }
        continue;
      }
      open.add((part: p.part!, instanceId: instance, index: slot.index, accept: slot.accept));
    }
  }
  final used = <String, int>{};
  final placed = <PlacedJewel>[];

  bool meets(Map<String, int> skills) {
    for (final e in request.targetSkills.entries) {
      if ((skills[e.key] ?? 0) < e.value) return false;
    }
    return true;
  }

  void rec(int i) {
    if (i == open.length) {
      final skills = <String, int>{};
      final sources = <String, List<String>>{};
      for (final p in pieces) {
        for (final g in p.skills) {
          skills[g.skillId] = (skills[g.skillId] ?? 0) + g.level;
          sources.putIfAbsent(g.skillId, () => []).add(p.entryId);
        }
      }
      for (final j in placed) {
        final jewel = jewels.firstWhere((e) => e.entryId == j.entryId);
        for (final g in jewel.skills) {
          skills[g.skillId] = (skills[g.skillId] ?? 0) + g.level;
          sources.putIfAbsent(g.skillId, () => []).add(j.entryId);
        }
      }
      if (!meets(skills)) return;
      var weaponOpen = reservedWeapon;
      var armorOpen = reservedArmor;
      for (final slot in open) {
        final filled = placed.any((j) => j.equipInstanceId == slot.instanceId && j.slotIndex == slot.index);
        if (!filled) {
          if (slot.part == 'weapon') {
            weaponOpen++;
          } else {
            armorOpen++;
          }
        }
      }
      final pieceIds = pieces.map((p) => p.entryId).toList()..sort();
      final jewelIds = placed.map((j) => '${j.equipInstanceId}:${j.slotIndex}:${j.entryId}').toList()..sort();
      found.add(Loadout(
        pieces: pieces.map((p) => PlacedPiece(p.part!, p.entryId, '${p.part}-${p.entryId}')).toList(),
        jewels: List<PlacedJewel>.from(placed),
        skills: skills,
        skillSources: sources,
        weaponOpen: weaponOpen,
        armorOpen: armorOpen,
        stableId: '${pieceIds.join('+')}|${jewelIds.join('+')}',
      ));
      return;
    }
    rec(i + 1); // leave this slot empty
    final slot = open[i];
    for (final jewel in jewels) {
      if (jewel.slotType != slot.accept) continue;
      if (request.useInventory) {
        final have = request.inventory[jewel.entryId] ?? 0;
        if ((used[jewel.entryId] ?? 0) >= have) continue;
      } else if ((used[jewel.entryId] ?? 0) >= open.length) {
        continue;
      }
      used[jewel.entryId] = (used[jewel.entryId] ?? 0) + 1;
      placed.add(PlacedJewel(jewel.entryId, slot.instanceId, slot.index, slot.part));
      rec(i + 1);
      placed.removeLast();
      used[jewel.entryId] = used[jewel.entryId]! - 1;
    }
  }

  rec(0);
}

String solveJson(String payload) {
  final map = jsonDecode(payload) as Map<String, dynamic>;
  final result = solve(
    SolveRequest.fromJson(map['request'] as Map<String, dynamic>),
    Catalog.fromJson(map['catalog'] as Map<String, dynamic>),
  );
  return jsonEncode(result.toJson());
}
