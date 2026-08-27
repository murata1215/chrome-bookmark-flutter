import 'package:flutter/material.dart';

/// URL の起動可否分類。
enum UrlKind {
  /// http/https。Chrome で開ける。
  openable,

  /// javascript: / chrome: / about: / data: / file: 等。開けないのでコピーのみ。
  copyOnly,
}

UrlKind classifyScheme(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return UrlKind.copyOnly;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return UrlKind.openable;
  return UrlKind.copyOnly;
}

/// ホスト名を取り出す。http(s) 以外や不正な URL では null。
String? hostOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri.host;
}

/// favicon 取得 URL。http/https 以外は null（呼び出し側でフォールバックアイコンを出す）。
String? faviconUrlFor(String url) {
  final host = hostOf(url);
  if (host == null) return null;
  return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
}

/// スキーム別のフォールバックアイコン。
IconData fallbackIconFor(String url) {
  final uri = Uri.tryParse(url);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  switch (scheme) {
    case 'javascript':
      return Icons.code;
    case 'chrome':
    case 'edge':
    case 'about':
      return Icons.settings;
    case 'file':
      return Icons.insert_drive_file;
    default:
      return Icons.link;
  }
}

/// 行のサブタイトル（ホスト → スキーム → 生 URL の順にフォールバック）。
String displaySubtitle(String url) {
  final host = hostOf(url);
  if (host != null) return host;
  final uri = Uri.tryParse(url);
  if (uri != null && uri.scheme.isNotEmpty) return '${uri.scheme}:';
  return url;
}

/// タイトルが無い場合の表示用フォールバック（短縮 URL）。
String shortenUrl(String url, {int maxLength = 60}) {
  if (url.length <= maxLength) return url;
  return '${url.substring(0, maxLength - 1)}…';
}

/// URL/タイトルからアバターの頭文字を作る（favicon を使わない設定時）。
/// `characters`（`package:flutter/material.dart` が re-export）を使い、
/// サロゲートペア等を1文字に壊さないようにする。
String initialAvatar(String? title, String url) {
  final source = (title != null && title.trim().isNotEmpty) ? title.trim() : (hostOf(url) ?? url);
  final chars = source.characters;
  if (chars.isEmpty) return '?';
  return chars.first.toUpperCase();
}
