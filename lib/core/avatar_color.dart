import 'package:flutter/material.dart';

import 'url_utils.dart';

/// ホスト名から決定論的に色相を決める。`String.hashCode` は実行系（VM/Web/AOT）
/// によって値が変わりうるため使わず、FNV-1a を明示実装する
/// （同じ URL は常にどの端末・どのビルドでも同じ色になる）。
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// 'www.' を剥がして正規化する（www.github.com と github.com を同色に）。
/// ホストが取れない URL（javascript: 等）はフル URL をそのままキーにする。
String _colorKeyOf(String url) {
  final host = hostOf(url);
  final key = host ?? url;
  return key.startsWith('www.') ? key.substring(4) : key;
}

/// ファビコンのフォールバック（イニシャルタイル）用の背景色・前景色のペア。
/// 彩度・明度を固定しているため、どの色相でも前景/背景のコントラストは
/// 概ね 5〜7:1 に保たれる。
({Color bg, Color fg}) avatarColorsFor(String url, Brightness brightness) {
  var hue = (_fnv1a(_colorKeyOf(url)) % 360).toDouble();
  // ★のアンバー色相帯（概ね 35〜60°）と被ると紛らわしいのでずらす。
  if (hue > 35 && hue < 60) hue += 40;

  return brightness == Brightness.light
      ? (
          bg: HSLColor.fromAHSL(1, hue, 0.42, 0.86).toColor(),
          fg: HSLColor.fromAHSL(1, hue, 0.62, 0.30).toColor(),
        )
      : (
          bg: HSLColor.fromAHSL(1, hue, 0.30, 0.26).toColor(),
          fg: HSLColor.fromAHSL(1, hue, 0.60, 0.78).toColor(),
        );
}
