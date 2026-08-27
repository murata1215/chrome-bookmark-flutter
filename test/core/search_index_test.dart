import 'package:chrome_bookmark_flutter/core/search/search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenize', () {
    test('空白区切りで小文字化する', () {
      expect(tokenize('  Git  Hub  '), ['git', 'hub']);
    });

    test('空文字列は空リスト', () {
      expect(tokenize(''), <String>[]);
      expect(tokenize('   '), <String>[]);
    });

    test('全角スペースも区切りになる（\\s は Unicode 空白を含む）', () {
      // Dart の RegExp の \s は U+3000（全角スペース）を含む Zs カテゴリにも一致する。
      expect(tokenize('git　hub'), ['git', 'hub']);
    });
  });

  group('matchesAll', () {
    test('AND 条件・部分一致・大文字小文字無視', () {
      const haystack = 'github - example/repo\nhttps://github.com/example/repo';
      expect(matchesAll(haystack, tokenize('git hub')), isTrue);
      expect(matchesAll(haystack, tokenize('GIT HUB')), isTrue);
      expect(matchesAll(haystack, tokenize('git nothere')), isFalse);
    });

    test('URL のみの一致でもヒットする', () {
      final haystack = '\nhttps://example.co.jp/review?ref=1'.toLowerCase();
      expect(matchesAll(haystack, tokenize('review')), isTrue);
    });

    test('空クエリは常に一致', () {
      expect(matchesAll('anything', const []), isTrue);
      expect(matchesAll('', tokenize('')), isTrue);
    });
  });
}
