import 'dart:convert';

import 'package:builds/builds.dart';
import 'package:catalog/catalog.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n.dart';
import 'shell.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> events = const [];
  final search = TextEditingController();
  String? seenGame;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = MhScope.of(context).gameId;
    if (seenGame == id) return;
    seenGame = id;
    _load();
  }

  Future<void> _load() async {
    final model = MhScope.of(context);
    final list = await model.events(model.gameId);
    if (mounted) setState(() => events = list);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final wide = isWide(context);
    final event = events.where((e) => e['status'] != 'revoked').cast<Map<String, dynamic>?>().firstWhere((e) => e != null, orElse: () => null);
    final titles = (event?['titles'] as Map?)?.cast<String, dynamic>() ?? {};
    final rewards = (event?['rewards'] as List?) ?? const [];
    final rewardName = rewards.isEmpty ? '' : ((rewards.first as Map)['names'] as Map)[model.locale] ?? ((rewards.first as Map)['names'] as Map)['zh-Hans'];
    final cards = [
      SectionCard(
        title: l10n.t('eventCard'),
        action: event == null ? null : MhButton(label: l10n.t('viewQuest'), onPressed: () => context.go('/g/${model.gameId}/events/${event['id']}')),
        child: event == null
            ? Text(l10n.t('noEvent'), style: TextStyle(color: p.ink, fontSize: 15, height: 1.55))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${titles[model.locale] ?? titles['zh-Hans']}', style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${event['timezone']} · ${event['endsAt']}', style: TextStyle(color: p.meta, fontSize: 13)),
                Text('${l10n.t('rewardSearch')}：$rewardName', style: TextStyle(color: p.meta, fontSize: 13)),
              ]),
      ),
      SectionCard(
        title: l10n.t('dataCard'),
        action: MhButton(label: model.offlineReady ? l10n.t('offlineReady') : l10n.t('viewUpdate'), onPressed: () => context.go('/offline')),
        child: Text(
          model.gameId == 'wilds' ? l10n.t('wilds') : l10n.t('world'),
          style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      if (model.gameId == 'world')
        SectionCard(
          title: l10n.t('map'),
          action: MhButton(label: l10n.t('openMap'), onPressed: () => context.go('/g/world/maps/fixture-ancient-forest')),
          child: Text('夹具古代树\n${l10n.t('rare')}', style: TextStyle(color: p.ink, fontSize: 15, height: 1.55)),
        ),
    ];
    return MhFrame(
      title: l10n.t('home'),
      gameId: model.gameId,
      child: ListView(
        padding: EdgeInsets.all(wide ? 24 : p.pagePad),
        children: [
          GameSwitch(),
          const SizedBox(height: 12),
          MhSearch(hint: l10n.t('searchHome'), controller: search, onChanged: (_) {}),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.go('/g/${model.gameId}/entries?q=${Uri.encodeQueryComponent(search.text)}'), child: Text(l10n.t('catalog'))),
          ),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final card in cards) Expanded(child: Padding(padding: const EdgeInsets.all(6), child: card))])
          else
            for (final card in cards) ...[card, const SizedBox(height: 12)],
        ],
      ),
    );
  }
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({required this.gameId, this.initialQuery = '', super.key});
  final String gameId;
  final String initialQuery;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final TextEditingController search = TextEditingController(text: widget.initialQuery);
  String kind = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final wide = isWide(context);
    final cat = model.cat(widget.gameId);
    final profile = widget.gameId == 'wilds' ? 'base' : model.profile;
    final hits = cat?.search(profile: profile, locale: model.locale, query: search.text, kind: kind) ?? const <SearchHit>[];
    final filters = [
      ('', '全部'),
      ('weapon', '武器'),
      ('armor', '防具'),
      ('monster', '怪物'),
      ('item', '道具'),
      ('skill', '技能'),
      ('material', '素材'),
      ('decoration', '饰品'),
    ];
    final filterBar = SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final item in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(item.$2, style: TextStyle(color: kind == item.$1 ? Colors.white : p.ink, fontWeight: FontWeight.w600)),
                selected: kind == item.$1,
                selectedColor: p.primary,
                backgroundColor: p.card,
                onSelected: (_) => setState(() => kind = item.$1),
              ),
            ),
        ],
      ),
    );
    final list = hits.isEmpty
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.t('emptyList'), style: TextStyle(fontSize: 15, color: p.ink)),
            const SizedBox(height: 8),
            MhButton(label: l10n.t('clearFilters'), onPressed: () => setState(() { kind = ''; search.clear(); })),
          ])
        : Column(
            children: [
              for (final hit in hits)
                InkWell(
                  onTap: () => context.go('/g/${widget.gameId}/entries/${hit.entry.kind}/${hit.entry.entryId}'),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: p.sheet, borderRadius: BorderRadius.circular(p.radiusCard)),
                    child: Row(children: [
                      Container(width: 40, height: 40, decoration: BoxDecoration(color: p.dark ? p.primary : p.ink, borderRadius: BorderRadius.circular(8)), child: Icon(_kindIcon(hit.entry.kind), color: p.dark ? Colors.white : p.onInk, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hit.entry.displayName(model.locale, cat!.defaultLocale), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
                        Text('${hit.entry.kind} · ${hit.entry.profiles.join('/')}${hit.fallbackLocale == null ? '' : ' · ${hit.fallbackLocale}'}', style: TextStyle(fontSize: 13, color: p.meta)),
                      ])),
                      Icon(LucideIcons.chevronRight, color: p.meta, size: 18),
                    ]),
                  ),
                ),
            ],
          );
    return MhFrame(
      title: l10n.t('catalog'),
      gameId: widget.gameId,
      child: Padding(
        padding: EdgeInsets.all(wide ? 24 : p.pagePad),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 220, child: filterBar),
                const SizedBox(width: 16),
                Expanded(child: ListView(children: [MhSearch(hint: l10n.t('searchWiki'), controller: search, onChanged: (_) => setState(() {})), const SizedBox(height: 12), list])),
              ])
            : ListView(children: [MhSearch(hint: l10n.t('searchWiki'), controller: search, onChanged: (_) => setState(() {})), const SizedBox(height: 12), filterBar, const SizedBox(height: 12), list]),
      ),
    );
  }
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'weapon':
      return LucideIcons.sword;
    case 'armor':
      return LucideIcons.shield;
    case 'monster':
      return LucideIcons.bug;
    case 'skill':
      return LucideIcons.star;
    case 'material':
      return LucideIcons.gem;
    default:
      return LucideIcons.box;
  }
}

class EntryPage extends StatelessWidget {
  const EntryPage({required this.gameId, required this.kind, required this.entryId, super.key});
  final String gameId;
  final String kind;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final wide = isWide(context);
    final cat = model.cat(gameId);
    final entry = cat?.entry(kind, entryId);
    final name = entry?.displayName(model.locale, cat?.defaultLocale ?? 'zh-Hans') ?? entryId;
    final fav = model.store.isFavorite(gameId, kind, entryId);
    final pois = kind == 'material' && gameId == 'world' ? (cat?.pois(resourceId: entryId) ?? const <MapPoi>[]) : const <MapPoi>[];
    return MhFrame(
      title: name,
      gameId: gameId,
      inner: true,
      favorited: fav,
      onFavorite: () => model.toggleFavorite(gameId, kind, entryId),
      child: entry == null
          ? Center(child: Text(l10n.t('missing')))
          : ListView(
              padding: EdgeInsets.all(wide ? 24 : p.pagePad),
              children: [
                if (wide) Text('百科 / $kind / $name', style: TextStyle(color: p.meta, fontSize: 13)),
                Text('$kind · ${gameId == 'wilds' ? l10n.t('wilds') : l10n.t('world')} · ${entry.profiles.join('/')}', style: TextStyle(color: p.meta, fontSize: 13, height: 1.45)),
                const SizedBox(height: 8),
                Text(entry.texts[model.locale]?.summary ?? entry.texts[cat!.defaultLocale]?.summary ?? '', style: TextStyle(fontSize: wide ? 16 : 15, height: 1.55, color: p.ink)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Fact(label: l10n.t('rarity'), value: '${entry.rarity}', palette: p),
                  if (entry.slots.isNotEmpty) _Fact(label: '孔', value: '${entry.slots.length}', palette: p),
                ]),
                const SizedBox(height: 12),
                for (final rel in cat!.fromEntry(kind, entryId))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(cat.byId(rel.toId)?.displayName(model.locale, cat.defaultLocale) ?? rel.toId, style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                    subtitle: Text(rel.type, style: TextStyle(color: p.meta)),
                    trailing: Icon(LucideIcons.chevronRight, color: p.meta),
                    onTap: () => context.go('/g/$gameId/entries/${rel.toKind}/${rel.toId}'),
                  ),
                if (pois.isNotEmpty)
                  SectionCard(
                    title: '出现地点',
                    action: MhButton(label: l10n.t('map'), primary: true, onPressed: () => context.go('/g/world/maps/fixture-ancient-forest?resource=$entryId')),
                    child: Text('${pois.first.area} · ${pois.first.layerId}\n${pois.first.conditions}', style: TextStyle(color: p.ink, height: 1.55)),
                  ),
                if (entry.fields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(const JsonEncoder.withIndent('  ').convert(entry.fields), style: TextStyle(color: p.ink, fontSize: 13, height: 1.45)),
                ],
              ],
            ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.palette});
  final String label;
  final String value;
  final MhPalette palette;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: palette.sheet, borderRadius: BorderRadius.circular(palette.radiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: palette.ink)),
        Text(label, style: TextStyle(fontSize: 13, color: palette.meta)),
      ]),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({required this.gameId, required this.mapId, this.resourceId, super.key});
  final String gameId;
  final String mapId;
  final String? resourceId;
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  String layer = 'floor-1';
  final kinds = <String>{'gather', 'rare-gather'};
  MapPoi? selected;
  bool tuned = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (tuned) return;
    tuned = true;
    final cat = MhScope.of(context).cat('world');
    final resource = widget.resourceId;
    if (cat == null || resource == null || resource.isEmpty) return;
    for (final map in cat.maps) {
      for (final poi in map.pois) {
        if (poi.resourceId == resource) {
          layer = poi.layerId;
          selected = poi;
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final wide = isWide(context);
    final cat = model.cat('world');
    GameMap? map;
    for (final item in cat?.maps ?? const <GameMap>[]) {
      if (item.mapId == widget.mapId) map = item;
    }
    final pois = (map?.pois ?? const <MapPoi>[]).where((poi) => poi.layerId == layer && kinds.contains(poi.kind)).toList();
    final title = map?.texts[model.locale]?.name ?? map?.texts['zh-Hans']?.name ?? l10n.t('map');
    final canvas = InteractiveViewer(
      minScale: 0.8,
      maxScale: 3,
      child: AspectRatio(
        aspectRatio: wide ? 1.2 : 1,
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _PaperMapPainter())),
          for (final poi in pois)
            Positioned(
              left: poi.xNorm * 280,
              top: poi.yNorm * 280,
              child: GestureDetector(
                onTap: () => setState(() => selected = poi),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: kinds.contains(poi.kind) ? p.accent : p.meta,
                    shape: BoxShape.circle,
                    border: selected?.poiId == poi.poiId ? Border.all(color: p.ink, width: 3) : null,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
    final info = selected == null
        ? Text(wide ? '点一个标记查看素材' : l10n.t('notDownloaded'), style: TextStyle(color: p.meta))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${selected!.kind} · ${selected!.layerId}', style: TextStyle(color: p.meta, fontSize: 13)),
            Text(selected!.resourceId, style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            Text('${selected!.area} · ${selected!.conditions}', style: TextStyle(color: p.ink, height: 1.45)),
            const SizedBox(height: 8),
            MhButton(label: l10n.t('viewMaterial'), primary: true, onPressed: () => context.go('/g/world/entries/${selected!.resourceKind}/${selected!.resourceId}')),
          ]);
    final filters = Wrap(spacing: 8, children: [
      for (final item in map?.layers ?? const [])
        ChoiceChip(
          label: Text(item.texts[model.locale]?.name ?? item.id, style: TextStyle(color: layer == item.id ? Colors.white : p.ink)),
          selected: layer == item.id,
          selectedColor: p.primary,
          backgroundColor: p.card,
          onSelected: (_) => setState(() { layer = item.id; selected = null; }),
        ),
      FilterChip(
        label: Text(l10n.t('rare'), style: TextStyle(color: kinds.contains('rare-gather') ? Colors.white : p.ink)),
        selected: kinds.contains('rare-gather'),
        selectedColor: p.primary,
        backgroundColor: p.card,
        onSelected: (v) => setState(() => v ? kinds.add('rare-gather') : kinds.remove('rare-gather')),
      ),
    ]);
    return MhFrame(
      title: title,
      gameId: 'world',
      inner: true,
      hideNav: !wide,
      child: Padding(
        padding: EdgeInsets.all(wide ? 24 : p.pagePad),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 240, child: filters),
                Expanded(child: canvas),
                SizedBox(width: 300, child: info),
              ])
            : Column(children: [filters, const SizedBox(height: 8), Expanded(child: canvas), const SizedBox(height: 8), info]),
      ),
    );
  }
}

class _PaperMapPainter extends CustomPainter {
  const _PaperMapPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = const Color(0xFFE7D7BC));
    final path = Path()..moveTo(size.width * 0.2, size.height * 0.25)..quadraticBezierTo(size.width * 0.5, size.height * 0.05, size.width * 0.75, size.height * 0.3)..quadraticBezierTo(size.width * 0.55, size.height * 0.45, size.width * 0.25, size.height * 0.4)..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF8AA8A0)..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BuildsPage extends StatefulWidget {
  const BuildsPage({required this.gameId, super.key});
  final String gameId;
  @override
  State<BuildsPage> createState() => _BuildsPageState();
}

class _BuildsPageState extends State<BuildsPage> {
  bool useInventory = true;
  bool reserve = false;
  bool running = false;
  bool assumeUnlimited = false;
  int generation = 0;
  int tab = 0;
  String? weaponId;
  final Map<String, int> targets = {};
  final Set<String> fixedIds = {};
  final Set<String> excludedIds = {};
  final Map<String, int> jewelCounts = {};
  SolveResult? result;
  String heard = '';
  final importCtrl = TextEditingController();
  final sentenceCtrl = TextEditingController();
  String? importMessage;
  bool seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (seeded) return;
    seeded = true;
    final cat = MhScope.of(context).cat(widget.gameId);
    if (cat == null) return;
    if (widget.gameId == 'wilds') {
      weaponId = 'fixture-weapon-w';
      fixedIds.addAll(['fixture-weapon-w', 'fixture-head-h']);
      targets['fixture-skill-y'] = 1;
    } else {
      weaponId = 'fixture-iron-sword';
      fixedIds.addAll(['fixture-fixed-mail', 'fixture-iron-sword']);
      targets['fixture-skill-s'] = 3;
      jewelCounts['fixture-attack-jewel'] = 2;
    }
    MhScope.of(context).loadAiStatus();
  }

  @override
  void dispose() {
    importCtrl.dispose();
    sentenceCtrl.dispose();
    super.dispose();
  }

  SolveRequest _request() {
    final model = MhScope.of(context);
    final wilds = widget.gameId == 'wilds';
    return SolveRequest(
      gameId: widget.gameId,
      contentProfile: wilds ? 'base' : model.profile,
      targetSkills: {for (final entry in targets.entries) if (entry.value > 0) entry.key: entry.value},
      fixedEquipment: fixedIds.toList(),
      excludedEquipment: excludedIds.toList(),
      useInventory: useInventory,
      inventory: Map<String, int>.from(jewelCounts),
      reserved: reserve && wilds ? [ReservedSlot(part: 'weapon', index: 0)] : const [],
    );
  }

  Future<void> _solve() async {
    final model = MhScope.of(context);
    final gen = ++generation;
    setState(() => running = true);
    final solved = await model.solve(widget.gameId, _request());
    if (!mounted || gen != generation) return;
    setState(() { running = false; result = solved; });
  }

  Future<void> _fromSentence() async {
    final model = MhScope.of(context);
    final body = await model.understand(sentenceCtrl.text);
    if (!mounted) return;
    if (body['httpStatus'] != 200) {
      setState(() => heard = '模型不可用，继续用条件配装。');
      return;
    }
    final cat = model.cat(widget.gameId);
    if (cat == null) return;
    final styles = (body['styles'] as List? ?? const []).map((e) => '$e').toList();
    final unsupported = <String>[];
    final mapped = targetsForStyles(styles, unsupported);
    setState(() {
      targets
        ..clear()
        ..addAll(mapped);
      assumeUnlimited = body['assumeUnlimitedJewels'] == true;
      useInventory = !assumeUnlimited;
      heard = '它听成了什么：武器 ${(body['weaponNames'] as List? ?? const []).join('、')}，风格 ${styles.join('、')}${unsupported.isEmpty ? '' : '。这版规则还不能算 ${unsupported.join('、')}'}';
    });
    if (mapped.isNotEmpty) await _solve();
  }

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final dark = p.dark;
    return MhFrame(
      title: l10n.t('builds'),
      gameId: widget.gameId,
      bottom: Row(children: [
        if (dark) ...[
          MhButton(label: l10n.t('stop'), danger: true, onPressed: running ? () => setState(() { generation++; running = false; }) : null),
          const SizedBox(width: 8),
        ],
        Expanded(child: MhButton(label: l10n.t('solve'), primary: true, onPressed: running ? null : _solve)),
      ]),
      child: ListView(
        padding: EdgeInsets.all(p.pagePad),
        children: [
          if (dark)
            Row(children: [
              for (final item in const [(0, '配装推荐'), (1, '配装器')])
                Expanded(child: InkWell(onTap: () => setState(() => tab = item.$1), child: Container(height: 36, alignment: Alignment.center, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == item.$1 ? p.accent : Colors.transparent, width: 2))), child: Text(item.$2)))),
            ])
          else ...[
            SectionCard(title: '自动配装', action: MhButton(label: l10n.t('solve'), onPressed: _solve), child: Text(widget.gameId == 'wilds' ? '按技能求解，可预留一个武器孔。' : '固定胸甲提供 1 级。两孔两珠才有解。', style: TextStyle(color: p.ink, height: 1.55))),
            const SizedBox(height: 12),
            SectionCard(title: '导入配装', child: Column(children: [
              TextField(controller: importCtrl, maxLines: 3, decoration: InputDecoration(hintText: l10n.t('import'), filled: true, fillColor: p.sheet)),
              const SizedBox(height: 8),
              MhButton(label: l10n.t('preview'), onPressed: () {
                final cat = model.cat(widget.gameId);
                if (cat == null) return;
                try {
                  final preview = previewBuild(jsonDecode(importCtrl.text) as Map<String, dynamic>, cat);
                  setState(() => importMessage = preview.ok ? '${preview.skills}' : preview.error);
                } catch (e) {
                  setState(() => importMessage = '$e');
                }
              }),
              if (importMessage != null) Text(importMessage!, style: TextStyle(color: p.meta)),
            ])),
          ],
          if (model.aiStatus?['showButton'] == true) ...[
            Text('用一句话配装。这句话会送到本站的配装服务，用来收成求解条件。', style: TextStyle(color: p.meta, fontSize: 13)),
            TextField(controller: sentenceCtrl, decoration: InputDecoration(hintText: '用这把武器打这只怪', filled: true, fillColor: p.sheet)),
            const SizedBox(height: 8),
            MhButton(label: '生成配装', primary: true, onPressed: running ? null : _fromSentence),
          ] else
            Text('模型未开通，使用条件配装。', style: TextStyle(color: p.meta, fontSize: 13)),
          if (heard.isNotEmpty) Text(heard),
          const SizedBox(height: 8),
          Text('条件', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
          for (final skill in (model.cat(widget.gameId)?.entries.where((e) => e.kind == 'skill').toList() ?? const <CatalogEntry>[]))
            Row(children: [
              Expanded(child: Text(skill.displayName(model.locale, 'zh-Hans'))),
              IconButton(onPressed: () => setState(() => targets[skill.entryId] = ((targets[skill.entryId] ?? 0) - 1).clamp(0, 7)), icon: const Icon(Icons.remove)),
              Text('${targets[skill.entryId] ?? 0}'),
              IconButton(onPressed: () => setState(() => targets[skill.entryId] = ((targets[skill.entryId] ?? 0) + 1).clamp(0, 7)), icon: const Icon(Icons.add)),
            ]),
          for (final jewel in (model.cat(widget.gameId)?.entries.where((e) => e.kind == 'decoration').toList() ?? const <CatalogEntry>[]))
            Row(children: [
              Expanded(child: Text(jewel.displayName(model.locale, 'zh-Hans'))),
              IconButton(onPressed: () {
                setState(() {
                  jewelCounts[jewel.entryId] = ((jewelCounts[jewel.entryId] ?? 0) - 1).clamp(0, 9);
                  model.store.setInventory(widget.gameId, jewel.entryId, jewelCounts[jewel.entryId] ?? 0);
                });
              }, icon: const Icon(Icons.remove)),
              Text('${jewelCounts[jewel.entryId] ?? 0}'),
              IconButton(onPressed: () {
                setState(() {
                  jewelCounts[jewel.entryId] = ((jewelCounts[jewel.entryId] ?? 0) + 1).clamp(0, 9);
                  model.store.setInventory(widget.gameId, jewel.entryId, jewelCounts[jewel.entryId] ?? 0);
                });
              }, icon: const Icon(Icons.add)),
            ]),
          SwitchListTile(value: useInventory, onChanged: (v) => setState(() { useInventory = v; assumeUnlimited = !v; }), title: Text(l10n.t('useJewels'))),
          if (widget.gameId == 'wilds') SwitchListTile(value: reserve, onChanged: (v) => setState(() => reserve = v), title: Text(l10n.t('reserve'))),
          if (result != null) _ResultView(result: result!, catalog: model.cat(widget.gameId), assumeUnlimited: assumeUnlimited, l10n: l10n, onSave: () {
            model.store.saveBuild(widget.gameId, 'local-${DateTime.now().millisecondsSinceEpoch}', {'title': '夹具配装', 'fixture': true});
          }),
          TextButton(onPressed: () => context.go('/builds/pub-fixture-wilds-1'), child: Text(l10n.t('hall'))),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.catalog, required this.assumeUnlimited, required this.l10n, required this.onSave});
  final SolveResult result;
  final Catalog? catalog;
  final bool assumeUnlimited;
  final L10n l10n;
  final VoidCallback onSave;
  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    if (catalog == null) return const SizedBox.shrink();
    final text = explainLoadout(result: result, catalog: catalog!, assumeUnlimited: assumeUnlimited, dataRevision: catalog!.dataRevision, fixture: catalog!.fixture);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(text.fixtureLine, style: TextStyle(color: p.skillOn, fontWeight: FontWeight.w700)),
      Text(result.searchComplete ? '已搜完' : l10n.t('partial'), style: TextStyle(color: p.meta)),
      for (final line in text.skillLines) Text(line, style: TextStyle(color: p.ink, height: 1.45)),
      Text(text.slotsLine, style: TextStyle(color: p.ink)),
      Text(text.assumption, style: TextStyle(color: p.meta, fontSize: 13)),
      for (final gap in text.gaps)
        gap.checked
            ? TextButton(onPressed: () => context.go('/g/${catalog!.gameId}/entries/monster/${gap.monsterId}'), child: Text('${gap.entryId} · ${gap.note}'))
            : Text(gap.note, style: TextStyle(color: p.meta)),
      if (!text.empty) MhButton(label: l10n.t('saveBuild'), onPressed: onSave),
    ]);
  }
}

class EventsPage extends StatefulWidget {
  const EventsPage({required this.gameId, super.key});
  final String gameId;
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final name = TextEditingController();
  final reward = TextEditingController();
  List<Map<String, dynamic>> rows = const [];
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await MhScope.of(context).events(widget.gameId, q: name.text, reward: reward.text);
      if (mounted) setState(() { rows = list; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n(MhScope.of(context).locale);
    final p = paletteOf(context);
    return MhFrame(
      title: l10n.t('events'),
      gameId: widget.gameId,
      inner: true,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.all(p.pagePad),
          child: Row(children: [
            Expanded(child: MhSearch(hint: l10n.t('search'), controller: name, onChanged: (_) {})),
            const SizedBox(width: 8),
            Expanded(child: MhSearch(hint: l10n.t('rewardSearch'), controller: reward, onChanged: (_) {})),
            IconButton(onPressed: _load, icon: Icon(LucideIcons.search, color: p.ink)),
          ]),
        ),
        if (error != null) MhButton(label: l10n.t('retry'), primary: true, onPressed: _load),
        Expanded(child: ListView(children: [
          for (final row in rows)
            ListTile(
              title: Text(((row['titles'] as Map?)?[MhScope.of(context).locale] ?? (row['titles'] as Map?)?['zh-Hans'] ?? row['id']).toString(), style: TextStyle(color: p.dark ? p.gold : p.ink, fontWeight: FontWeight.w700)),
              subtitle: Text('${row['status']}', style: TextStyle(color: p.meta)),
              onTap: () => context.go('/g/${widget.gameId}/events/${row['id']}'),
            ),
        ])),
      ]),
    );
  }
}

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({required this.gameId, required this.id, super.key});
  final String gameId;
  final String id;
  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    return MhFrame(
      title: l10n.t('events'),
      gameId: gameId,
      inner: true,
      child: FutureBuilder(
        future: model.event(id),
        builder: (context, snap) {
          if (snap.hasError) return MhButton(label: l10n.t('retry'), primary: true, onPressed: () => context.go('/g/$gameId/events/$id'));
          final row = snap.data;
          if (row == null) return const Center(child: CircularProgressIndicator());
          if (row['code'] != null) return Text(l10n.t('missing'));
          final titles = (row['titles'] as Map?)?.cast<String, dynamic>() ?? {};
          return ListView(padding: EdgeInsets.all(p.pagePad), children: [
            Text('${titles[model.locale] ?? titles['zh-Hans'] ?? id}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.dark ? p.gold : p.ink)),
            Text('${l10n.t('verified')} ${row['verifiedAt']}', style: TextStyle(color: p.meta, fontSize: 13)),
            const SizedBox(height: 8),
            Container(height: 10, decoration: BoxDecoration(color: p.dark ? p.bar : p.barOff, borderRadius: BorderRadius.circular(999)), child: FractionallySizedBox(widthFactor: 0.6, alignment: Alignment.centerLeft, child: DecoratedBox(decoration: BoxDecoration(color: p.dark ? const Color(0xFFFE9700) : p.accent, borderRadius: BorderRadius.circular(999))))),
            const SizedBox(height: 8),
            Text('${row['conditions']}', style: TextStyle(color: p.ink, height: 1.55)),
            Text('${row['timezone']} ${row['startsAt']} → ${row['endsAt']}', style: TextStyle(color: p.meta)),
            for (final raw in (row['rewards'] as List? ?? const []))
              Builder(builder: (context) {
                final reward = Map<String, dynamic>.from(raw as Map);
                final itemId = reward['itemId']?.toString() ?? '';
                final names = reward['names'] is Map ? Map<String, dynamic>.from(reward['names'] as Map) : const <String, dynamic>{};
                return TextButton(
                  onPressed: () {
                    final kind = model.cat(gameId)?.byId(itemId)?.kind ?? 'item';
                    context.go('/g/$gameId/entries/$kind/$itemId');
                  },
                  child: Text('${names['zh-Hans'] ?? '报酬'}'),
                );
              }),
          ]);
        },
      ),
    );
  }
}

class PublicBuildPage extends StatelessWidget {
  const PublicBuildPage({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    return MhFrame(
      title: l10n.t('hall'),
      child: FutureBuilder(
        future: model.publicBuild(id),
        builder: (context, snap) {
          final row = snap.data;
          if (row == null) return const Center(child: CircularProgressIndicator());
          if (row['httpStatus'] == 410 || row['code'] == 'RETRACTED') {
            return Center(child: Text(l10n.t('retractedTitle'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.ink)));
          }
          if (row['httpStatus'] == 404 || row['code'] == 'NOT_FOUND') return Center(child: Text(l10n.t('missing')));
          return ListView(padding: EdgeInsets.all(p.pagePad), children: [
            Text(row['title']?.toString() ?? id, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.ink)),
            Text(catalogFixtureLine(row), style: TextStyle(color: p.skillOn)),
            const SizedBox(height: 8),
            Text(const JsonEncoder.withIndent('  ').convert(row['snapshot']), style: TextStyle(color: p.ink, height: 1.45)),
            const SizedBox(height: 12),
            MhButton(label: l10n.t('copyMine'), primary: true, onPressed: () {
              model.store.saveBuild(row['gameId']?.toString() ?? 'world', 'copy-$id', {'title': row['title'], 'source': id, 'snapshot': row['snapshot']});
            }),
            const SizedBox(height: 8),
            MhButton(label: l10n.t('copyLink'), onPressed: () => Clipboard.setData(ClipboardData(text: Uri.base.toString()))),
            const SizedBox(height: 8),
            SelectableText(Uri.base.toString(), style: TextStyle(color: p.meta, fontSize: 13)),
          ]);
        },
      ),
    );
  }
}

String catalogFixtureLine(Map<String, dynamic> row) {
  final snap = row['snapshot'];
  if (snap is Map && snap['dataRevision'] != null) {
    return '夹具，不是游戏实数。${snap['dataRevision']}';
  }
  return '夹具，不是游戏实数。';
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final userCtrl = TextEditingController(text: 'hunter-a');
  String info = '';

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    final builds = [...model.store.builds('world'), ...model.store.builds('wilds')];
    return MhFrame(
      title: l10n.t('me'),
      child: ListView(padding: EdgeInsets.all(p.pagePad), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.sheet, borderRadius: BorderRadius.circular(p.radiusCard)),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle), child: Icon(LucideIcons.user, color: p.onInk)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(model.userId ?? l10n.t('guest'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
              Text(l10n.t('guestHint'), style: TextStyle(fontSize: 13, color: p.meta)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        if (model.userId == null) MhButton(label: l10n.t('loginSync'), onPressed: () async {
          await model.login(userCtrl.text.trim());
          final ent = await model.entitlement();
          setState(() => info = '$ent');
        }) else MhButton(label: l10n.t('logout'), onPressed: () async { await model.logout(); setState(() => info = ''); }),
        const SizedBox(height: 12),
        _group(p, [
          _row(p, LucideIcons.star, l10n.t('favorite'), '${model.favorites.length}'),
          _row(p, LucideIcons.gem, '我的装饰品', ''),
          _row(p, LucideIcons.shield, l10n.t('builds'), '${builds.length}'),
          _row(p, LucideIcons.user, '会员空间', model.userId == null ? l10n.t('notEnabled') : info),
        ]),
        const SizedBox(height: 12),
        _group(p, [
          _row(p, LucideIcons.globe, l10n.t('language'), model.locale, onTap: () => _cycleLocale(model)),
          _row(p, LucideIcons.bell, '提醒', '站内'),
          Semantics(
            button: true,
            label: '切换外观',
            child: _row(p, LucideIcons.sun, l10n.t('theme'), model.themeName == 'dark' ? '深色' : '浅色', onTap: () => model.setTheme(model.themeName == 'dark' ? 'light' : 'dark')),
          ),
          _row(p, LucideIcons.download, l10n.t('offline'), model.offlineReady ? l10n.t('offlineReady') : l10n.t('notDownloaded'), onTap: () => context.go('/offline')),
        ]),
      ]),
    );
  }

  void _cycleLocale(dynamic model) {
    const codes = L10n.codes;
    final i = codes.indexOf(model.locale);
    model.setLocale(codes[(i + 1) % codes.length]);
  }

  Widget _group(MhPalette p, List<Widget> rows) => Container(
    decoration: BoxDecoration(color: p.sheet, borderRadius: BorderRadius.circular(p.radiusCard)),
    child: Column(children: rows),
  );

  Widget _row(MhPalette p, IconData icon, String title, String trailing, {VoidCallback? onTap}) => ListTile(
    leading: Icon(icon, color: p.ink, size: 18),
    title: Text(title, style: TextStyle(color: p.ink, fontWeight: FontWeight.w500)),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(trailing, style: TextStyle(color: p.meta, fontSize: 13)), Icon(LucideIcons.chevronRight, color: p.meta, size: 16)]),
    onTap: onTap,
  );
}

class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});
  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  String message = '';

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final l10n = L10n(model.locale);
    final p = paletteOf(context);
    return MhFrame(
      title: l10n.t('offline'),
      inner: true,
      child: ListView(padding: EdgeInsets.all(p.pagePad), children: [
        for (final game in ['world', 'wilds'])
          SectionCard(
            title: game == 'world' ? l10n.t('world') : l10n.t('wilds'),
            action: MhButton(
              label: message.startsWith('fail') ? l10n.t('retry') : l10n.t('download'),
              primary: true,
              onPressed: () async {
                final msg = await model.download(game);
                setState(() => message = msg == 'ready' ? l10n.t('offlineReady') : 'fail $msg');
              },
            ),
            child: Text('fixture-1 · ${model.cat(game)?.dataRevision ?? l10n.t('notDownloaded')}\n$message', style: TextStyle(color: p.meta, fontSize: 13, height: 1.45)),
          ),
      ]),
    );
  }
}
