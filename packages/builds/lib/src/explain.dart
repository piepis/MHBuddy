import 'package:catalog/catalog.dart';

import 'solver.dart';

/// Human-maintained style words. Empty targets mean this ruleset cannot compute that style.
const Map<String, Map<String, int>> styleTargets = {
  '输出': {'fixture-skill-s': 3},
  '攻击': {'fixture-skill-s': 3},
  '生存': {},
  '会心': {},
  '辅助': {},
};

class MaterialGap {
  MaterialGap({required this.entryId, required this.checked, this.monsterId, this.note = ''});
  final String entryId;
  final bool checked;
  final String? monsterId;
  final String note;
}

class Explanation {
  Explanation({
    required this.searchComplete,
    required this.empty,
    required this.fixtureLine,
    required this.skillLines,
    required this.slotsLine,
    required this.assumption,
    required this.gaps,
  });
  final bool searchComplete;
  final bool empty;
  final String fixtureLine;
  final List<String> skillLines;
  final String slotsLine;
  final String assumption;
  final List<MaterialGap> gaps;
}

Explanation explainLoadout({
  required SolveResult result,
  required Catalog catalog,
  required bool assumeUnlimited,
  required String dataRevision,
  required bool fixture,
}) {
  final fixtureLine = fixture ? '夹具，不是游戏实数。资料版本 $dataRevision。' : '资料版本 $dataRevision。';
  if (result.fieldErrors.isNotEmpty) {
    return Explanation(searchComplete: true, empty: true, fixtureLine: fixtureLine, skillLines: result.fieldErrors, slotsLine: '', assumption: '', gaps: const []);
  }
  if (!result.searchComplete && result.loadouts.isEmpty) {
    return Explanation(searchComplete: false, empty: true, fixtureLine: fixtureLine, skillLines: const ['搜索中断，还没有完整结果。'], slotsLine: '', assumption: '', gaps: const []);
  }
  if (result.loadouts.isEmpty) {
    return Explanation(searchComplete: result.searchComplete, empty: true, fixtureLine: fixtureLine, skillLines: const ['按现在的珠和目标，没有更好的一套。'], slotsLine: '', assumption: '', gaps: const []);
  }
  final loadout = result.loadouts.first;
  final lines = <String>[];
  loadout.skillSources.forEach((skill, sources) {
    final level = loadout.skills[skill] ?? 0;
    final name = catalog.byId(skill)?.displayName('zh-Hans', catalog.defaultLocale) ?? skill;
    lines.add('$name $level 级，来自 ${sources.join('、')}');
  });
  return Explanation(
    searchComplete: result.searchComplete,
    empty: false,
    fixtureLine: fixtureLine,
    skillLines: lines,
    slotsLine: '武器空孔 ${loadout.weaponOpen}，防具空孔 ${loadout.armorOpen}',
    assumption: assumeUnlimited ? '未填写持有珠，这一套假设珠子够用。' : '按填写的装饰品数量计算。',
    gaps: gapsFor(catalog, loadout),
  );
}

List<MaterialGap> gapsFor(Catalog catalog, Loadout loadout) {
  final gaps = <MaterialGap>[];
  for (final piece in loadout.pieces) {
    final entry = catalog.byId(piece.entryId);
    if (entry == null) continue;
    for (final rel in catalog.fromEntry(entry.kind, entry.entryId)) {
      if (rel.type != 'craftedFrom') continue;
      final drops = catalog.toEntry(rel.toKind, rel.toId).where((r) => r.type == 'drops').toList();
      if (drops.isEmpty) {
        gaps.add(MaterialGap(entryId: rel.toId, checked: false, note: '这条还没有核对过的获取方式'));
      } else {
        gaps.add(MaterialGap(entryId: rel.toId, checked: true, monsterId: drops.first.fromId, note: '掉落'));
      }
    }
  }
  return gaps;
}

/// Unsupported style words are returned separately and must not be sent to the solver as invented skills.
Map<String, int> targetsForStyles(List<String> styles, List<String> unsupported) {
  final out = <String, int>{};
  for (final style in styles) {
    final table = styleTargets[style];
    if (table == null || table.isEmpty) {
      unsupported.add(style);
      continue;
    }
    table.forEach((skill, level) {
      final current = out[skill] ?? 0;
      if (level > current) out[skill] = level;
    });
  }
  return out;
}
