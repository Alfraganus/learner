import 'dart:io';

import 'package:flutter/material.dart';

/// "Study Studio" dizayn tizimi: iliq qog'oz + siyoh, serif o'qish matni, iris urg'u.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.paper,
    required this.border,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.warm,
    required this.warmSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.rail,
    required this.onRail,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color paper;
  final Color border;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color warm;
  final Color warmSoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color rail;
  final Color onRail;

  static const light = Palette(
    bg: Color(0xFFF3F0E8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF9F7F1),
    paper: Color(0xFFFFFDF8),
    border: Color(0xFFE5E0D3),
    ink: Color(0xFF1D1B16),
    inkSoft: Color(0xFF47433A),
    muted: Color(0xFF8B8577),
    accent: Color(0xFF5B4BDB),
    accentSoft: Color(0xFFECE9FD),
    onAccent: Color(0xFFFFFFFF),
    warm: Color(0xFFDB8B1E),
    warmSoft: Color(0xFFFCF0DC),
    success: Color(0xFF2E9A68),
    successSoft: Color(0xFFE2F4EA),
    danger: Color(0xFFD0453A),
    dangerSoft: Color(0xFFFBE7E4),
    rail: Color(0xFF1D1B16),
    onRail: Color(0xFFF3F0E8),
  );

  static const dark = Palette(
    bg: Color(0xFF12110E),
    surface: Color(0xFF1B1A16),
    surfaceAlt: Color(0xFF22211C),
    paper: Color(0xFF191814),
    border: Color(0xFF302E27),
    ink: Color(0xFFF1EDE4),
    inkSoft: Color(0xFFCDC7BB),
    muted: Color(0xFF8F897D),
    accent: Color(0xFF9F92FF),
    accentSoft: Color(0xFF29254A),
    onAccent: Color(0xFF15131F),
    warm: Color(0xFFF0B354),
    warmSoft: Color(0xFF3A2D17),
    success: Color(0xFF4CC48C),
    successSoft: Color(0xFF173226),
    danger: Color(0xFFF07467),
    dangerSoft: Color(0xFF3B1D19),
    rail: Color(0xFF0B0A08),
    onRail: Color(0xFFF1EDE4),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      paper: l(paper, other.paper),
      border: l(border, other.border),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      warm: l(warm, other.warm),
      warmSoft: l(warmSoft, other.warmSoft),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      rail: l(rail, other.rail),
      onRail: l(onRail, other.onRail),
    );
  }
}

/// Shriftlar: tizim shriftlari (oflayn ishlaydi, kirill va o'zbek lotini to'liq).
class Fonts {
  static String get ui => Platform.isMacOS ? '.AppleSystemUIFont' : 'Segoe UI Variable Text';
  static String get display =>
      Platform.isMacOS ? '.AppleSystemUIFontDisplay' : 'Segoe UI Variable Display';
  static const serif = 'Georgia';
  static String get mono => Platform.isMacOS ? 'Menlo' : 'Consolas';

  static const uiFallback = ['Segoe UI', 'Helvetica Neue', 'Ubuntu', 'Noto Sans', 'Arial'];
  static const serifFallback = ['Charter', 'Cambria', 'Noto Serif', 'Times New Roman'];
  static const monoFallback = ['Cascadia Code', 'Consolas', 'Menlo', 'DejaVu Sans Mono', 'monospace'];
}

extension PaletteX on BuildContext {
  Palette get pal => Theme.of(this).extension<Palette>()!;
  TextTheme get tt => Theme.of(this).textTheme;
}

TextStyle serif(BuildContext context,
    {double size = 18, FontWeight weight = FontWeight.w400, Color? color, double height = 1.7}) {
  return TextStyle(
    fontFamily: Fonts.serif,
    fontFamilyFallback: Fonts.serifFallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? context.pal.ink,
  );
}

TextStyle display(BuildContext context,
    {double size = 28, FontWeight weight = FontWeight.w700, Color? color, double height = 1.15}) {
  return TextStyle(
    fontFamily: Fonts.display,
    fontFamilyFallback: Fonts.uiFallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: -0.4,
    color: color ?? context.pal.ink,
  );
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.accentSoft,
    onPrimaryContainer: p.ink,
    secondary: p.warm,
    onSecondary: p.ink,
    secondaryContainer: p.warmSoft,
    onSecondaryContainer: p.ink,
    tertiary: p.success,
    onTertiary: p.surface,
    error: p.danger,
    onError: p.surface,
    errorContainer: p.dangerSoft,
    onErrorContainer: p.ink,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.inkSoft,
    surfaceContainerLowest: p.paper,
    surfaceContainerLow: p.surfaceAlt,
    surfaceContainer: p.surfaceAlt,
    surfaceContainerHigh: p.bg,
    surfaceContainerHighest: p.border,
    outline: p.muted,
    outlineVariant: p.border,
    shadow: Colors.black,
    inverseSurface: p.ink,
    onInverseSurface: p.bg,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: Fonts.ui,
    fontFamilyFallback: Fonts.uiFallback,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
  );

  final r12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final btnText = TextStyle(
    fontFamily: Fonts.ui,
    fontFamilyFallback: Fonts.uiFallback,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: r12,
        textStyle: btnText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: r12,
        textStyle: btnText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        shape: r12,
        textStyle: btnText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.inkSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      side: BorderSide(color: p.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: p.bg, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.border,
      circularTrackColor: p.border,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.muted.withValues(alpha: 0.35)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
