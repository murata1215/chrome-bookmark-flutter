import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/url_utils.dart';

/// URL 用のアバター。favicon 取得が有効な設定の時だけ実際の画像を出し、
/// それ以外は頭文字アバター（§7「解析・第三者送信なし」との緊張関係、既定 OFF）。
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
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final initial = initialAvatar(title, url);
    final fallback = CircleAvatar(
      radius: size / 2,
      child: Text(initial, style: TextStyle(fontSize: size * 0.4)),
    );

    if (!faviconEnabled) return fallback;

    final iconUrl = faviconUrlFor(url);
    if (iconUrl == null) {
      return CircleAvatar(
        radius: size / 2,
        child: Icon(fallbackIconFor(url), size: size * 0.55),
      );
    }

    // Chrome の favicon と同じ、角丸スクエアで表示（正方形画像の四隅が
    // 円形クリップで削れて別サイトに見えるのを防ぐ）。
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: iconUrl,
        width: size,
        height: size,
        memCacheWidth: 64,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, _) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}
