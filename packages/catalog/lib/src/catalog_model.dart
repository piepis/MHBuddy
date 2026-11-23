import 'dart:convert';

class EntryText {
  EntryText({required this.name, required this.aliases, required this.summary});
  final String name;
  final List<String> aliases;
  final String summary;

  static EntryText fromJson(Map<String, dynamic> json) => EntryText(
        name: json['name'] as String? ?? '',
        aliases: (json['aliases'] as List? ?? const []).map((e) => '$e').toList(),
        summary: json['summary'] as String? ?? '',
      );
}

class CatalogEntry {
  CatalogEntry({
    required this.gameId,
    required this.kind,
    required this.entryId,
    required this.rarity,
    required this.profiles,
    required this.platforms,
    required this.texts,
    required this.fields,
    required this.fixture,
    this.part,
    this.slotType,
    this.slots = const [],
    this.skills = const [],
  });

  final String gameId;
  final String kind;
  final String entryId;
  final int rarity;
  final List<String> profiles;
  final List<String> platforms;
  final Map<String, EntryText> texts;
  final Map<String, dynamic> fields;
  final bool fixture;
  final String? part;
  final String? slotType;
  final List<SlotDef> slots;
  final List<SkillGrant> skills;

  String displayName(String locale, String fallbackLocale) {
    final text = texts[locale] ?? texts[fallbackLocale] ?? texts.values.first;
    return text.name;
  }

  bool get usedFallback => false;
}

class SlotDef {
  SlotDef(this.index, this.accept);
  final int index;
  final String accept;
}

class SkillGrant {
  SkillGrant(this.skillId, this.level);
  final String skillId;
  final int level;
}

class CatalogRelation {
  CatalogRelation({required this.type, required this.fromKind, required this.fromId, required this.toKind, required this.toId});
  final String type;
  final String fromKind;
  final String fromId;
  final String toKind;
  final String toId;
}

class MapPoi {
  MapPoi({
    required this.poiId,
    required this.layerId,
    required this.xNorm,
    required this.yNorm,
    required this.area,
    required this.kind,
    required this.resourceKind,
    required this.resourceId,
    required this.conditions,
    required this.sourceRef,
  });
  final String poiId;
  final String layerId;
  final double xNorm;
  final double yNorm;
  final String area;
  final String kind;
  final String resourceKind;
  final String resourceId;
  final String conditions;
  final String sourceRef;
}

class GameMap {
  GameMap({required this.mapId, required this.profiles, required this.texts, required this.layers, required this.pois});
  final String mapId;
  final List<String> profiles;
  final Map<String, EntryText> texts;
  final List<({String id, Map<String, EntryText> texts})> layers;
  final List<MapPoi> pois;
}

class SearchHit {
  SearchHit(this.entry, this.fallbackLocale);
  final CatalogEntry entry;
  final String? fallbackLocale;
}

class Catalog {
  Catalog({
    required this.source,
    required this.gameId,
    required this.dataRevision,
    required this.revisionNumber,
    required this.rulesetVersion,
    required this.patchId,
    required this.defaultLocale,
    required this.fixture,
    required this.entries,
    required this.relations,
    required this.maps,
  });

  final Map<String, dynamic> source;
  final String gameId;
  final String dataRevision;
  final int revisionNumber;
  final String rulesetVersion;
  final String patchId;
  final String defaultLocale;
  final bool fixture;
  final List<CatalogEntry> entries;
  final List<CatalogRelation> relations;
  final List<GameMap> maps;

  static Catalog fromJson(Map<String, dynamic> json) {
    final gameId = json['gameId'] as String;
    final entries = (json['entries'] as List).map((raw) {
      final e = raw as Map<String, dynamic>;
      final texts = <String, EntryText>{};
      (e['texts'] as Map<String, dynamic>).forEach((k, v) {
        texts[k] = EntryText.fromJson(v as Map<String, dynamic>);
      });
      return CatalogEntry(
        gameId: gameId,
        kind: e['kind'] as String,
        entryId: e['entryId'] as String,
        rarity: (e['rarity'] as num?)?.toInt() ?? 0,
        profiles: (e['profiles'] as List? ?? ['base']).map((x) => '$x').toList(),
        platforms: (e['platforms'] as List? ?? const []).map((x) => '$x').toList(),
        texts: texts,
        fields: (e['fields'] as Map?)?.cast<String, dynamic>() ?? {},
        fixture: e['fixture'] == true,
        part: e['part'] as String?,
        slotType: e['slotType'] as String?,
        slots: (e['slots'] as List? ?? const []).map((s) {
          final m = s as Map<String, dynamic>;
          return SlotDef((m['index'] as num).toInt(), m['accept'] as String);
        }).toList(),
        skills: (e['skills'] as List? ?? const []).map((s) {
          final m = s as Map<String, dynamic>;
          return SkillGrant(m['skillId'] as String, (m['level'] as num).toInt());
        }).toList(),
      );
    }).toList();
    final relations = (json['relations'] as List? ?? const []).map((raw) {
      final r = raw as Map<String, dynamic>;
      return CatalogRelation(
        type: r['type'] as String,
        fromKind: r['fromKind'] as String,
        fromId: r['fromId'] as String,
        toKind: r['toKind'] as String,
        toId: r['toId'] as String,
      );
    }).toList();
    final maps = (json['maps'] as List? ?? const []).map((raw) {
      final m = raw as Map<String, dynamic>;
      final texts = <String, EntryText>{};
      (m['texts'] as Map<String, dynamic>).forEach((k, v) => texts[k] = EntryText.fromJson(v as Map<String, dynamic>));
      final layers = (m['layers'] as List).map((rawLayer) {
        final layer = rawLayer as Map<String, dynamic>;
        final lt = <String, EntryText>{};
        (layer['texts'] as Map<String, dynamic>).forEach((k, v) => lt[k] = EntryText.fromJson(v as Map<String, dynamic>));
        return (id: layer['layerId'] as String, texts: lt);
      }).toList();
      final pois = (m['pois'] as List).map((rawPoi) {
        final p = rawPoi as Map<String, dynamic>;
        final ref = p['resourceRef'] as Map<String, dynamic>;
        return MapPoi(
          poiId: p['poiId'] as String,
          layerId: p['layerId'] as String,
          xNorm: (p['xNorm'] as num).toDouble(),
          yNorm: (p['yNorm'] as num).toDouble(),
          area: p['area'] as String,
          kind: p['kind'] as String,
          resourceKind: ref['kind'] as String,
          resourceId: ref['entryId'] as String,
          conditions: p['conditions'] as String? ?? '',
          sourceRef: p['sourceRef'] as String? ?? '',
        );
      }).toList();
      return GameMap(
        mapId: m['mapId'] as String,
        profiles: (m['profiles'] as List? ?? const []).map((e) => '$e').toList(),
        texts: texts,
        layers: layers,
        pois: pois,
      );
    }).toList();
    return Catalog(
      source: json,
      gameId: gameId,
      dataRevision: json['dataRevision'] as String,
      revisionNumber: (json['revisionNumber'] as num?)?.toInt() ?? 1,
      rulesetVersion: json['rulesetVersion'] as String? ?? '',
      patchId: json['patchId'] as String? ?? '',
      defaultLocale: json['defaultLocale'] as String? ?? 'zh-Hans',
      fixture: json['fixture'] == true,
      entries: entries,
      relations: relations,
      maps: maps,
    );
  }

  static Catalog decode(String source) => Catalog.fromJson(jsonDecode(source) as Map<String, dynamic>);

  CatalogEntry? entry(String kind, String id) {
    for (final e in entries) {
      if (e.kind == kind && e.entryId == id) return e;
    }
    return null;
  }

  CatalogEntry? byId(String id) {
    for (final e in entries) {
      if (e.entryId == id) return e;
    }
    return null;
  }

  bool profileAllows(CatalogEntry e, String profile) {
    if (profile == 'base') return e.profiles.contains('base');
    if (profile == 'iceborne') return e.profiles.contains('base') || e.profiles.contains('iceborne');
    return true;
  }

  List<SearchHit> search({
    required String profile,
    required String locale,
    String query = '',
    String? kind,
    int? rarity,
    String? skillId,
    int offset = 0,
    int limit = 50,
  }) {
    final q = normalize(query);
    final hits = <SearchHit>[];
    for (final e in entries) {
      if (!profileAllows(e, profile)) continue;
      if (kind != null && kind.isNotEmpty && e.kind != kind) continue;
      if (rarity != null && e.rarity != rarity) continue;
      if (skillId != null && skillId.isNotEmpty && !_hasSkill(e, skillId)) continue;
      String? fallback;
      if (q.isNotEmpty) {
        final text = e.texts[locale];
        final used = text ?? e.texts[defaultLocale];
        if (text == null) fallback = defaultLocale;
        if (used == null || !_matches(used, q)) continue;
      } else if (!e.texts.containsKey(locale)) {
        fallback = defaultLocale;
      }
      hits.add(SearchHit(e, fallback));
    }
    hits.sort((a, b) => a.entry.entryId.compareTo(b.entry.entryId));
    if (offset >= hits.length) return const [];
    final end = offset + limit > hits.length ? hits.length : offset + limit;
    return hits.sublist(offset, end);
  }

  bool _hasSkill(CatalogEntry e, String skillId) {
    if (e.kind == 'skill' && e.entryId == skillId) return true;
    for (final s in e.skills) {
      if (s.skillId == skillId) return true;
    }
    for (final r in relations) {
      if (r.toKind == 'skill' && r.toId == skillId && r.fromId == e.entryId) return true;
    }
    return false;
  }

  bool _matches(EntryText text, String q) {
    final blob = normalize('${text.name} ${text.aliases.join(' ')} ${text.summary}');
    return blob.contains(q);
  }

  List<CatalogRelation> fromEntry(String kind, String id) =>
      relations.where((r) => r.fromKind == kind && r.fromId == id).toList();

  List<CatalogRelation> toEntry(String kind, String id) =>
      relations.where((r) => r.toKind == kind && r.toId == id).toList();

  List<MapPoi> pois({String? mapId, String? layerId, String? kind, String? resourceId}) {
    final out = <MapPoi>[];
    for (final map in maps) {
      if (mapId != null && map.mapId != mapId) continue;
      for (final poi in map.pois) {
        if (layerId != null && poi.layerId != layerId) continue;
        if (kind != null && poi.kind != kind) continue;
        if (resourceId != null && poi.resourceId != resourceId) continue;
        out.add(poi);
      }
    }
    return out;
  }
}

String normalize(String input) {
  final units = <int>[];
  for (final r in input.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60;
    if (c == 0x3000) c = 0x20;
    if (c >= 65 && c <= 90) c += 32;
    units.add(c);
  }
  return String.fromCharCodes(units).trim();
}
