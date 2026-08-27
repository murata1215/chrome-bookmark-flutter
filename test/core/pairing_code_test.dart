import 'package:chrome_bookmark_flutter/core/pairing_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractPairingCode', () {
    test('①信頼ホストの URL + 有効な code クエリを採用する', () {
      expect(
        extractPairingCode('https://chrome-bookmark.devrelay.io/pair?code=12345678'),
        '12345678',
      );
    });

    test('①信頼ホストでもパスやクエリの並びが違っても code を拾える', () {
      expect(
        extractPairingCode('https://chrome-bookmark.devrelay.io/x/y?foo=bar&code=00011122'),
        '00011122',
      );
    });

    test('①信頼ホストだが code が8桁数字でなければ拒否する（他分岐へフォールバックしない）', () {
      expect(
        extractPairingCode('https://chrome-bookmark.devrelay.io/pair?code=abcdefgh'),
        isNull,
      );
      expect(
        extractPairingCode('https://chrome-bookmark.devrelay.io/pair'),
        isNull,
      );
    });

    test('②生の8桁数字文字列を採用する', () {
      expect(extractPairingCode('12345678'), '12345678');
      expect(extractPairingCode('  87654321  '), '87654321');
    });

    test('②8桁ちょうどでなければ拒否する', () {
      expect(extractPairingCode('1234567'), isNull);
      expect(extractPairingCode('123456789'), isNull);
      expect(extractPairingCode('1234 5678'), isNull);
    });

    test('③どちらでもなければ null（読み取り継続）', () {
      expect(extractPairingCode(''), isNull);
      expect(extractPairingCode('hello world'), isNull);
      expect(extractPairingCode('javascript:alert(1)'), isNull);
    });

    test('悪意あるホストは code クエリを含んでいても拒否する', () {
      expect(
        extractPairingCode('https://evil.example.com/pair?code=12345678'),
        isNull,
      );
      // 信頼ホストに見せかけたサブドメイン・別ホストも拒否。
      expect(
        extractPairingCode('https://chrome-bookmark.devrelay.io.evil.com/pair?code=12345678'),
        isNull,
      );
      expect(
        extractPairingCode('https://notchrome-bookmark.devrelay.io/pair?code=12345678'),
        isNull,
      );
    });
  });
}
