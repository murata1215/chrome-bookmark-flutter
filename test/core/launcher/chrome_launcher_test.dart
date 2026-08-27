import 'package:chrome_bookmark_flutter/core/launcher/chrome_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iosChromeSchemeFor', () {
    test('https は googlechromes: に書き換わる', () {
      expect(
        iosChromeSchemeFor('https://example.com/'),
        'googlechromes://example.com/',
      );
    });

    test('http は googlechrome: に書き換わる', () {
      expect(
        iosChromeSchemeFor('http://example.com/'),
        'googlechrome://example.com/',
      );
    });

    test('クエリとフラグメントが保存される', () {
      expect(
        iosChromeSchemeFor('https://example.com/path?a=1&b=2#frag'),
        'googlechromes://example.com/path?a=1&b=2#frag',
      );
    });

    test('http/https 以外は null（呼び出し側で他の手段にフォールバックする）', () {
      expect(iosChromeSchemeFor('javascript:alert(1)'), isNull);
      expect(iosChromeSchemeFor('chrome://bookmarks'), isNull);
      expect(iosChromeSchemeFor('ftp://example.com/'), isNull);
    });

    test('userinfo や IDN ホストを含む URL でも scheme 部分だけが変わる（Uri.replace は使わない）', () {
      // Uri.replace(scheme:) は path/query を再正規化しうるが、生文字列の
      // replaceFirst は先頭の一致部分だけを書き換えるので影響しない。
      expect(
        iosChromeSchemeFor('https://user:pass@xn--fsq.example/'),
        'googlechromes://user:pass@xn--fsq.example/',
      );
    });
  });
}
