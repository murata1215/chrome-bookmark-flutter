import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 一覧の視認性重視・密度高めのテーマ。
///
/// light/dark は共通の [_build] から派生させる。かつては dark() にだけ
/// `appBarTheme` が無い等の非対称があったため、構造的に起こり得ない形にした。
class AppTheme {
  /// インディゴ・バイオレット。Chrome のブランド色（Google Blue #1A73E8）から
  /// 色相を離し、商標的な連想を避ける。★のアンバー（AppSemanticColors.star）
  /// とはほぼ補色の関係にあり、一覧内で「頻度バー＝紫」「★＝金」が混ざらない。
  static const seed = Color(0xFF5B4FD1);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final sem = AppSemanticColors.of(s);
    final base = ThemeData(brightness: brightness, colorScheme: s, useMaterial3: true);

    return base.copyWith(
      extensions: [sem],
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: s.surface,
      textTheme: _textTheme(base.textTheme),

      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        surfaceTintColor: s.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 2,
        backgroundColor: s.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (st) => TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: st.contains(WidgetState.selected) ? s.onSurface : s.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (st) => IconThemeData(
            size: 24,
            color:
                st.contains(WidgetState.selected) ? s.onSecondaryContainer : s.onSurfaceVariant,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: s.surfaceContainerHighest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),

      listTileTheme: ListTileThemeData(
        dense: true,
        minTileHeight: AppSpacing.rowMinHeight,
        minVerticalPadding: 4,
        horizontalTitleGap: 10,
        minLeadingWidth: 24,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.rowH),
        titleTextStyle: base.textTheme.bodyLarge?.copyWith(
          fontSize: 14.5,
          height: 1.25,
          color: s.onSurface,
        ),
        subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
          fontSize: 11.5,
          height: 1.1,
          color: s.onSurfaceVariant,
        ),
        iconColor: s.onSurfaceVariant,
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: s.outlineVariant.withValues(alpha: 0.6),
      ),

      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: s.surfaceContainerHigh,
        hintStyle: TextStyle(color: s.onSurfaceVariant, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: s.primary, width: 1.5),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: false,
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        backgroundColor: s.inverseSurface,
        contentTextStyle: TextStyle(color: s.onInverseSurface, fontSize: 13.5),
        actionTextColor: s.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSpacing.tapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.primary,
        linearTrackColor: s.surfaceContainerHighest,
      ),
    );
  }

  /// プラットフォーム既定フォント（iOS=SF Pro+ヒラギノ／Android=Roboto+Noto Sans JP）
  /// のまま、weight・letterSpacing・height だけ整える。
  /// google_fonts は起動時に外部へ取得しに行くためプライバシー方針と衝突し不採用。
  /// CJK フォント同梱はフルセットで 8〜12MB とランチャーの軽さに見合わず不採用。
  static TextTheme _textTheme(TextTheme b) {
    return b.copyWith(
      titleLarge: b.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.25,
      ),
      titleMedium: b.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
      bodyLarge: b.bodyLarge?.copyWith(letterSpacing: 0, height: 1.3),
      bodyMedium: b.bodyMedium?.copyWith(letterSpacing: 0, height: 1.35),
      bodySmall: b.bodySmall?.copyWith(letterSpacing: 0.1, height: 1.2),
      labelLarge: b.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      // 回数・件数などの数字が行ごとに桁ズレして見えるのを防ぐ（等幅数字）。
      labelSmall: b.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
