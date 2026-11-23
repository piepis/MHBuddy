import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'app_model.dart';
import 'l10n.dart';
import 'theme.dart';

class MhScope extends InheritedNotifier<AppModel> {
  const MhScope({required AppModel model, required super.child, super.key}) : super(notifier: model);
  static AppModel of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MhScope>()!.notifier!;
}

MhPalette paletteOf(BuildContext context) => MhPalette.of(MhScope.of(context).themeName);

class MhFrame extends StatelessWidget {
  const MhFrame({
    required this.title,
    required this.child,
    this.gameId,
    this.inner = false,
    this.onFavorite,
    this.favorited = false,
    this.hideNav = false,
    this.bottom,
    super.key,
  });

  final String title;
  final Widget child;
  final String? gameId;
  final bool inner;
  final VoidCallback? onFavorite;
  final bool favorited;
  final bool hideNav;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final p = paletteOf(context);
    final l10n = L10n(model.locale);
    final wide = isWide(context);
    final id = gameId ?? model.gameId;
    return Theme(
      data: mhTheme(model.themeName, model.locale),
      child: Scaffold(
        backgroundColor: p.paper,
        body: SafeArea(
          child: Column(
            children: [
              if (wide)
                _WideBar(title: title, l10n: l10n, gameId: id, palette: p, favorited: favorited, onFavorite: onFavorite)
              else
                _PhoneBar(
                  title: title,
                  palette: p,
                  inner: inner,
                  favorited: favorited,
                  onFavorite: onFavorite,
                  onMenu: () => _openMenu(context, model, l10n),
                ),
              Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1120), child: child))),
              if (bottom != null) Padding(padding: EdgeInsets.fromLTRB(p.pagePad, 0, p.pagePad, 8), child: bottom),
              if (!wide && !hideNav) _BottomNav(l10n: l10n, gameId: id, palette: p),
            ],
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, AppModel model, L10n l10n) {
    final p = paletteOf(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.sheet,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(LucideIcons.globe, color: p.ink), title: Text(l10n.t('language')), onTap: () { Navigator.pop(context); context.go('/me'); }),
            ListTile(
              leading: Icon(LucideIcons.sun, color: p.ink),
              title: Text(l10n.t('theme')),
              subtitle: Text(model.themeName == 'dark' ? l10n.t('themeDark') : l10n.t('themeLight')),
              onTap: () {
                model.setTheme(model.themeName == 'dark' ? 'light' : 'dark');
                Navigator.pop(context);
              },
            ),
            ListTile(leading: Icon(LucideIcons.download, color: p.ink), title: Text(l10n.t('offline')), onTap: () { Navigator.pop(context); context.go('/offline'); }),
          ],
        ),
      ),
    );
  }
}

class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.title, required this.palette, required this.inner, required this.favorited, required this.onFavorite, required this.onMenu});
  final String title;
  final MhPalette palette;
  final bool inner;
  final bool favorited;
  final VoidCallback? onFavorite;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final iconBg = palette.dark ? Colors.white : palette.ink;
    final iconFg = palette.dark ? palette.onWhite : palette.onInk;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _IconTap(
            background: iconBg,
            iconColor: iconFg,
            icon: inner ? LucideIcons.chevronLeft : LucideIcons.menu,
            onTap: inner
              ? () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                }
              : onMenu,
          ),
          Expanded(child: Text(title, textAlign: TextAlign.center, style: TextStyle(color: palette.ink, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25))),
          if (onFavorite != null)
            Semantics(
              button: true,
              label: favorited ? '取消收藏' : '收藏',
              child: _IconTap(
                background: favorited ? (palette.dark ? palette.primary : palette.accent) : iconBg,
                iconColor: Colors.white,
                icon: LucideIcons.star,
                onTap: onFavorite!,
              ),
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.background, required this.iconColor, required this.icon, required this.onTap});
  final Color background;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}

class _WideBar extends StatelessWidget {
  const _WideBar({required this.title, required this.l10n, required this.gameId, required this.palette, this.onFavorite, this.favorited = false});
  final String title;
  final L10n l10n;
  final String gameId;
  final MhPalette palette;
  final VoidCallback? onFavorite;
  final bool favorited;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final items = [
      (l10n.t('home'), '/'),
      (l10n.t('catalog'), '/g/$gameId/entries'),
      (l10n.t('builds'), '/g/$gameId/builds'),
      (l10n.t('me'), '/me'),
    ];
    return ColoredBox(
      color: palette.paperBar,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(l10n.t('app'), style: TextStyle(color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(width: 24),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: InkWell(
                    onTap: () => context.go(item.$2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _on(path, item.$2) ? palette.accent : Colors.transparent, width: 2))),
                      child: Text(item.$1, style: TextStyle(color: palette.ink, fontSize: 15, fontWeight: _on(path, item.$2) ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  ),
                ),
              const Spacer(),
              if (onFavorite != null)
                Semantics(
                  button: true,
                  label: favorited ? l10n.t('favorited') : l10n.t('favorite'),
                  child: IconButton(
                    onPressed: onFavorite,
                    icon: Icon(LucideIcons.star, color: favorited ? palette.accent : palette.ink),
                  ),
                ),
              Text(title, style: TextStyle(color: palette.meta, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  bool _on(String path, String route) {
    if (route == '/') return path == '/';
    if (route == '/me') return path == '/me' || path == '/offline';
    return path.startsWith(route);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.l10n, required this.gameId, required this.palette});
  final L10n l10n;
  final String gameId;
  final MhPalette palette;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final items = [
      (l10n.t('home'), '/', LucideIcons.house),
      (l10n.t('catalog'), '/g/$gameId/entries', LucideIcons.bookOpen),
      (l10n.t('builds'), '/g/$gameId/builds', LucideIcons.shield),
      (l10n.t('me'), '/me', LucideIcons.user),
    ];
    return ColoredBox(
      color: palette.tabbar,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: InkWell(
                  onTap: () => context.go(item.$2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$3, size: 22, color: _on(path, item.$2) ? palette.tabActive : palette.tabInactive),
                      const SizedBox(height: 2),
                      Text(item.$1, style: TextStyle(fontSize: 12, fontWeight: _on(path, item.$2) ? FontWeight.w700 : FontWeight.w500, color: _on(path, item.$2) ? palette.tabActive : palette.tabInactive)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _on(String path, String route) {
    if (route == '/') return path == '/';
    if (route == '/me') return path == '/me' || path == '/offline';
    return path.startsWith(route);
  }
}

class GameSwitch extends StatelessWidget {
  const GameSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final model = MhScope.of(context);
    final p = paletteOf(context);
    final l10n = L10n(model.locale);
    return Container(
      height: 36,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(p.radiusCard), color: p.segmentOff),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final item in [('world', l10n.t('worldShort')), ('wilds', l10n.t('wilds'))])
            Expanded(
              child: Semantics(
                button: true,
                selected: model.gameId == item.$1,
                label: item.$2,
                child: InkWell(
                onTap: () {
                  model.setGame(item.$1);
                  final path = GoRouterState.of(context).uri.path;
                  if (path == '/' || RegExp(r'^/g/[^/]+$').hasMatch(path)) context.go('/g/${item.$1}');
                },
                child: Container(
                  color: model.gameId == item.$1 ? (p.dark ? p.primary : p.accent) : p.segmentOff,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: p.gameDot(item.$1), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(item.$2, style: TextStyle(color: model.gameId == item.$1 ? Colors.white : p.ink, fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.child, this.action, super.key});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return Container(
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(p.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: p.dark ? 36 : 40,
            color: p.dark ? const Color(0xFF1C3348) : p.ink,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(title, style: TextStyle(color: p.dark ? const Color(0xFFF8FEFF) : p.onInk, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [child, if (action != null) ...[const SizedBox(height: 12), Center(child: action!)]]),
          ),
        ],
      ),
    );
  }
}

class MhButton extends StatelessWidget {
  const MhButton({required this.label, required this.onPressed, this.primary = false, this.danger = false, super.key});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    final bg = danger ? p.danger : (primary ? p.primary : Colors.white);
    final fg = primary || danger ? Colors.white : p.onWhite;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 32,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: p.segmentOff,
            elevation: 0,
            minimumSize: const Size(96, 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.radiusButton)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class MhSearch extends StatelessWidget {
  const MhSearch({required this.hint, required this.onChanged, this.controller, super.key});
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final p = paletteOf(context);
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: p.ink, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.meta, fontSize: 15),
          prefixIcon: Icon(LucideIcons.search, color: p.meta, size: 18),
          filled: true,
          fillColor: p.sheet,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(p.radiusButton), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
