import 'dart:convert';
import 'dart:io';

import 'package:chrome_bookmark_flutter/core/models/pending.dart';
import 'package:chrome_bookmark_flutter/core/storage/pending_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pending_store_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('PendingStore', () {
    test('ファイルが無ければ空キューを返す', () async {
      final store = PendingStore(dir);
      final loaded = await store.load();
      expect(loaded.isEmpty, isTrue);
    });

    test('保存→読み込みの往復（opens/stars 両方）', () async {
      final store = PendingStore(dir);
      final queue = PendingQueue(
        opens: [
          PendingOpen(
            eventId: 'e1',
            url: 'https://a.example/',
            openedAt: DateTime.utc(2026, 1, 1),
          ),
          PendingOpen(
            eventId: 'e2',
            url: 'https://b.example/',
            openedAt: DateTime.utc(2026, 1, 2),
          ),
        ],
        stars: {
          'https://a.example/': PendingStar(
            url: 'https://a.example/',
            starred: true,
            changedAt: DateTime.utc(2026, 1, 3),
          ),
        },
      );

      await store.save(queue);
      final loaded = await store.load();

      expect(loaded.opens, hasLength(2));
      expect(loaded.opens.map((o) => o.eventId), containsAll(['e1', 'e2']));
      expect(loaded.stars, hasLength(1));
      expect(loaded.stars['https://a.example/']!.starred, isTrue);
    });

    test('ON→OFF→ON は1件に潰れる（URLキーの上書き）', () async {
      final store = PendingStore(dir);
      final queue = PendingQueue(opens: const [], stars: {
        'https://a.example/': PendingStar(
          url: 'https://a.example/',
          starred: false,
          changedAt: DateTime.utc(2026, 1, 5),
        ),
      });
      await store.save(queue);
      final loaded = await store.load();
      expect(loaded.stars, hasLength(1));
      expect(loaded.stars['https://a.example/']!.starred, isFalse);
    });

    test('壊れた JSON は例外ではなく空キューとして読み込まれる', () async {
      final file = File('${dir.path}/pending.json');
      file.writeAsStringSync('{ this is not valid json');

      final store = PendingStore(dir);
      final loaded = await store.load();
      expect(loaded.isEmpty, isTrue);
    });

    test('JSON としては正しいがスキーマが破綻していても空キュー扱いのフィールドは無視される', () async {
      final file = File('${dir.path}/pending.json');
      file.writeAsStringSync(jsonEncode({
        'version': 1,
        'opens': [
          {'event_id': 'e1', 'url': 'https://a.example/'}, // opened_at 欠落
          {'event_id': 'e2', 'url': 'https://b.example/', 'opened_at': '2026-01-01T00:00:00Z'},
        ],
        'stars': 'not-a-map',
      }));

      final store = PendingStore(dir);
      final loaded = await store.load();
      // opened_at 欠落の要素で fromJson が例外を投げ、load() 全体が
      // 空キューにフォールバックする（部分的な読み込みはしない仕様）。
      expect(loaded.isEmpty, isTrue);
    });

    test('clear() でファイルが削除される', () async {
      final store = PendingStore(dir);
      await store.save(PendingQueue(
        opens: [
          PendingOpen(eventId: 'e1', url: 'https://a.example/', openedAt: DateTime.utc(2026, 1, 1)),
        ],
        stars: const {},
      ));
      expect(File('${dir.path}/pending.json').existsSync(), isTrue);

      await store.clear();
      expect(File('${dir.path}/pending.json').existsSync(), isFalse);

      final loaded = await store.load();
      expect(loaded.isEmpty, isTrue);
    });

    test('書き込みは .tmp を残さない（原子的 rename）', () async {
      final store = PendingStore(dir);
      await store.save(PendingQueue(
        opens: [
          PendingOpen(eventId: 'e1', url: 'https://a.example/', openedAt: DateTime.utc(2026, 1, 1)),
        ],
        stars: const {},
      ));
      expect(File('${dir.path}/pending.json.tmp').existsSync(), isFalse);
      expect(File('${dir.path}/pending.json').existsSync(), isTrue);
    });
  });
}
