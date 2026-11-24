import 'package:material_ui/material_ui.dart';

import 'theme_dom_stub.dart' if (dart.library.html) 'theme_dom_web.dart';

class MhPalette {
  const MhPalette({
    required this.dark,
    required this.paper,
    required this.paperBar,
    required this.card,
    required this.sheet,
    required this.ink,
    required this.onInk,
    required this.meta,
    required this.accent,
    required this.onAccent,
    required this.segmentOff,
    required this.bar,
    required this.barOff,
    required this.skillOn,
    required this.line,
    required this.tabbar,
    required this.tabActive,
    required this.tabInactive,
    required this.onWhite,
    required this.primary,
    required this.danger,
    required this.gold,
    required this.banner,
    required this.gameWorld,
    required this.gameWilds,
    required this.radiusCard,
    required this.radiusButton,
    required this.pagePad,
  });

  final bool dark;
  final Color paper;
  final Color paperBar;
  final Color card;
  final Color sheet;
  final Color ink;
  final Color onInk;
  final Color meta;
  final Color accent;
  final Color onAccent;
  final Color segmentOff;
  final Color bar;
  final Color barOff;
  final Color skillOn;
  final Color line;
  final Color tabbar;
  final Color tabActive;
  final Color tabInactive;
  final Color onWhite;
  final Color primary;
  final Color danger;
  final Color gold;
  final Color banner;
  final Color gameWorld;
  final Color gameWilds;
  final double radiusCard;
  final double radiusButton;
  final double pagePad;

  Color gameDot(String gameId) => gameId == 'wilds' ? gameWilds : gameWorld;

  static const lightPalette = MhPalette(
    dark: false,
    paper: Color(0xFFD9CBAF),
    paperBar: Color(0xFFEFE6D4),
    card: Color(0xFFE1D7C4),
    sheet: Color(0xFFF4EFE4),
    ink: Color(0xFF2D1B08),
    onInk: Color(0xFFE5D9C6),
    meta: Color(0xFF5C5140),
    accent: Color(0xFF991E45),
    onAccent: Color(0xFFFFFFFF),
    segmentOff: Color(0xFFB9AE97),
    bar: Color(0xFF376AC9),
    barOff: Color(0xFFA7A099),
    skillOn: Color(0xFF8A3A4C),
    line: Color(0x242D1B08),
    tabbar: Color(0xFF000000),
    tabActive: Color(0xFFC4C4DC),
    tabInactive: Color(0xFFB2B3B2),
    onWhite: Color(0xFF2E2F2F),
    primary: Color(0xFF991E45),
    danger: Color(0xFFC62828),
    gold: Color(0xFF2D1B08),
    banner: Color(0xFF2D1B08),
    gameWorld: Color(0xFF376AC9),
    gameWilds: Color(0xFF991E45),
    radiusCard: 2,
    radiusButton: 999,
    pagePad: 12,
  );

  static const darkPalette = MhPalette(
    dark: true,
    paper: Color(0xFF13273C),
    paperBar: Color(0xFF1E3D4A),
    card: Color(0xFF15283A),
    sheet: Color(0xFF15283A),
    ink: Color(0xFFD4DEE2),
    onInk: Color(0xFFF8FEFF),
    meta: Color(0xFFB7C4CC),
    accent: Color(0xFF50D4ED),
    onAccent: Color(0xFF102028),
    segmentOff: Color(0xFF1C3348),
    bar: Color(0xFF50D4ED),
    barOff: Color(0xFF505153),
    skillOn: Color(0xFFF1D95C),
    line: Color(0x29D4DEE2),
    tabbar: Color(0xFF000000),
    tabActive: Color(0xFF0DA9B7),
    tabInactive: Color(0xFF858585),
    onWhite: Color(0xFF192336),
    primary: Color(0xFF0277A3),
    danger: Color(0xFFC62828),
    gold: Color(0xFFF1D95C),
    banner: Color(0xFF244D9C),
    gameWorld: Color(0xFF50D4ED),
    gameWilds: Color(0xFFF1D95C),
    radiusCard: 10,
    radiusButton: 7,
    pagePad: 16,
  );

  static MhPalette of(String name) => name == 'dark' ? darkPalette : lightPalette;
}

String fontForLocale(String code) {
  switch (code) {
    case 'zh-Hant':
      return 'Noto Sans TC';
    case 'ja':
      return 'Noto Sans JP';
    case 'en':
      return 'Noto Sans';
    default:
      return 'Noto Sans SC';
  }
}

ThemeData mhTheme(String name, String locale) {
  final p = MhPalette.of(name);
  final font = fontForLocale(locale);
  final base = p.dark ? Typography.material2021().white : Typography.material2021().black;
  return ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: p.paper,
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    fontFamily: font,
    colorScheme: ColorScheme(
      brightness: p.dark ? Brightness.dark : Brightness.light,
      primary: p.primary,
      onPrimary: Colors.white,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: p.danger,
      onError: Colors.white,
      surface: p.sheet,
      onSurface: p.ink,
    ),
    dividerColor: p.line,
    textTheme: base.apply(bodyColor: p.ink, displayColor: p.ink, fontFamily: font),
    focusColor: p.accent,
  );
}

void applyDataTheme(String name) => setDataTheme(name == 'dark' ? 'dark' : 'light');

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 720;
