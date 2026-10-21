import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/avatar_color.dart';
import '../core/design_tokens.dart';
import '../core/url_utils.dart';

/// URL 用のアバター。favicon 取得が有効な設定の時だけ実際の画像を出し、
/// それ以外は頭文字アバター（§7「解析・第三者送信なし」との緊張関係、既定 OFF）。
///
/// どの分岐でも同じ角丸スクエアの外形（[shell]）を返す。以前は実画像が角丸
/// スクエア・フォールバックが真円で、読み込み完了時に形がフリップしていた。
/// フォールバックの背景色はホスト名から決定論的に決める（[avatarColorsFor]）
/// ので、favicon を OFF にしていても一覧が色づき、同じサイトは常に同じ色になる。
class FaviconAvatar extends StatelessWidget {
  final String url;
  final String? title;
  final bool faviconEnabled;
  final double size;

  const FaviconAvatar({
    super.key,
    required this.url,
    required this.title,
    required this.faviconEnabled,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = avatarColorsFor(url, brightness);
    final radius = BorderRadius.circular(AppRadius.avatar);

    Widget shell(Widget child, {required Color bg}) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: child,
      );
    }

    final fallback = shell(
      Text(
        initialAvatar(title, url),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * 0.52,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: colors.fg,
        ),
      ),
      bg: colors.bg,
    );

    if (!faviconEnabled) return fallback;

    final iconUrl = faviconUrlFor(url);
    if (iconUrl == null) {
      // chrome:// や javascript: 等。スキーム別アイコンもホスト同色のタイルに乗せる。
      return shell(
        Icon(fallbackIconFor(url), size: size * 0.6, color: colors.fg),
        bg: colors.bg,
      );
    }

    // placeholder/errorWidget は既に shell() 済みの fallback をそのまま使うので、
    // 成功時の画像だけ同じ外形（角丸スクエア）でクリップする。
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: iconUrl,
        width: size,
        height: size,
        memCacheWidth: 96,
        fit: BoxFit.cover,
        fadeInDuration: AppMotion.fast,
        placeholder: (context, _) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}
