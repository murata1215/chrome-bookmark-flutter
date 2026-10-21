import 'package:flutter/material.dart';

/// 明暗で値が変わる「意味を持つ色」だけを置く。`ColorScheme` に該当スロットが
/// 無いもの（★・リンク切れ・メーター・スケルトン）が対象。
/// 寸法・時間（[AppRadius] / [AppSpacing] / [AppMotion]）は明暗で変わらないので
/// あえて `ThemeExtension` にせず `static const` にしている。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color star;
  final Color starIdle;
  final Color offline;
  final Color meterTrack;
  final Color meterFill;
  final Color meterFillTop;
  final Color skeletonBase;
  final Color skeletonHighlight;

  const AppSemanticColors({
    required this.star,
    required this.starIdle,
    required this.offline,
    required this.meterTrack,
    required this.meterFill,
    required this.meterFillTop,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  /// 非テキスト要素のコントラスト 3:1 以上を満たす値を選定済み。
  ///   light star #C77800 → 白地 3.24:1 / dark star #FFC96B → #141218 上 12:1
  factory AppSemanticColors.of(ColorScheme s) {
    return s.brightness == Brightness.light
        ? AppSemanticColors(
            star: const Color(0xFFC77800),
            starIdle: s.outline,
            offline: s.onSurfaceVariant,
            meterTrack: s.surfaceContainerHighest,
            meterFill: s.primary.withValues(alpha: 0.45),
            meterFillTop: s.primary,
            skeletonBase: s.surfaceContainerHighest,
            skeletonHighlight: s.surfaceContainerLow,
          )
        : AppSemanticColors(
            star: const Color(0xFFFFC96B),
            starIdle: s.outline,
            offline: s.onSurfaceVariant,
            meterTrack: s.surfaceContainerHigh,
            meterFill: s.primary.withValues(alpha: 0.55),
            meterFillTop: s.primary,
            skeletonBase: s.surfaceContainerHigh,
            skeletonHighlight: s.surfaceContainerHighest,
          );
  }

  @override
  AppSemanticColors copyWith({
    Color? star,
    Color? starIdle,
    Color? offline,
    Color? meterTrack,
    Color? meterFill,
    Color? meterFillTop,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return AppSemanticColors(
      star: star ?? this.star,
      starIdle: starIdle ?? this.starIdle,
      offline: offline ?? this.offline,
      meterTrack: meterTrack ?? this.meterTrack,
      meterFill: meterFill ?? this.meterFill,
      meterFillTop: meterFillTop ?? this.meterFillTop,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      star: Color.lerp(star, other.star, t)!,
      starIdle: Color.lerp(starIdle, other.starIdle, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      meterTrack: Color.lerp(meterTrack, other.meterTrack, t)!,
      meterFill: Color.lerp(meterFill, other.meterFill, t)!,
      meterFillTop: Color.lerp(meterFillTop, other.meterFillTop, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
    );
  }
}

/// `Theme.of(context).colorScheme` / `.extension<AppSemanticColors>()!` を
/// 1 行で済ませるための拡張。全ウィジェットでこれを使う。
extension AppThemeX on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  AppSemanticColors get sem => Theme.of(this).extension<AppSemanticColors>()!;
}

abstract final class AppRadius {
  static const double card = 16;
  static const double avatar = 6; // ファビコン／フォルダタイルの角丸。実画像とフォールバックで共通。
  static const double pill = 28;
  static const double chip = 8;
}

abstract final class AppSpacing {
  static const double rowH = 12; // 行の左右パディング
  static const double rowMinHeight = 48;
  static const double tapTarget = 44; // iOS HIG / Material 共通の最小タップ領域
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120); // ファビコン fade 等
  static const Duration standard = Duration(milliseconds: 200); // タブ・バー出入り
  static const Duration emphasized = Duration(milliseconds: 260); // 階層遷移・★トグル
  static const Curve curve = Curves.easeOutCubic;
  static const Curve curveIn = Curves.easeInCubic;

  /// 「視差効果を減らす」設定時は Duration.zero を返す（a11y 対応をここに集約）。
  static Duration of(BuildContext context, Duration base) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : base;
}
