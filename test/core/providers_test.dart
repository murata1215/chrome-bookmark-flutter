import 'package:chrome_bookmark_flutter/core/models/flat_bookmark.dart';
import 'package:chrome_bookmark_flutter/core/models/mark.dart';
import 'package:chrome_bookmark_flutter/core/models/pending.dart';
import 'package:chrome_bookmark_flutter/core/providers.dart';
import 'package:chrome_bookmark_flutter/core/storage/prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// effectiveMarksProvider は読み出しの都度 prefsProvider（clampOpenedAt 用の
/// serverNow）を watch するため、このグループのテストは override が必須。
Future<AppPrefs> _testPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return AppPrefs.create();
}

Mark _mark(
  String url, {
  bool starred = false,
  DateTime? starredAt,
  int openCount = 0,
  double score = 0,
  DateTime? scoreAt,
  DateTime? lastOpenedAt,
  required DateTime updatedAt,
  String? title,
}) =>
    Mark(
      url: url,
      starred: starred,
      starredAt: starredAt,
      openCount: openCount,
      score: score,
      scoreAt: scoreAt,
      lastOpenedAt: lastOpenedAt,
      updatedAt: updatedAt,
      title: title,
    );

void main() {
  group('MarksNotifier.mergeFromServer', () {
    test('サーバーが新しい（updated_at 以上）場合は適用される', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', openCount: 1, updatedAt: DateTime.utc(2026, 1, 1)),
      });

      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://a.example/', openCount: 2, updatedAt: DateTime.utc(2026, 1, 2)),
      ]);

      expect(container.read(marksProvider)['https://a.example/']!.openCount, 2);
    });

    test('ローカルの updated_at より古い応答は無視される', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', openCount: 5, updatedAt: DateTime.utc(2026, 1, 10)),
      });

      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://a.example/', openCount: 1, updatedAt: DateTime.utc(2026, 1, 1)), // 古い
      ]);

      expect(container.read(marksProvider)['https://a.example/']!.openCount, 5);
    });

    test('updated_at が同時刻でも適用される（isBefore は strict）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final t = DateTime.utc(2026, 1, 1);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', openCount: 1, updatedAt: t),
      });
      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://a.example/', openCount: 9, updatedAt: t),
      ]);

      expect(container.read(marksProvider)['https://a.example/']!.openCount, 9);
    });

    test('title はクライアント専用なので既存値が生き残る', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', updatedAt: DateTime.utc(2026, 1, 1), title: 'My Title'),
      });

      // サーバー応答には title が含まれない（null）。
      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://a.example/', updatedAt: DateTime.utc(2026, 1, 2)),
      ]);

      expect(container.read(marksProvider)['https://a.example/']!.title, 'My Title');
    });

    test('新規 URL はそのまま追加される', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://new.example/', updatedAt: DateTime.utc(2026, 1, 1)),
      ]);

      expect(container.read(marksProvider).containsKey('https://new.example/'), isTrue);
    });
  });

  group('MarksNotifier.applyTitles', () {
    test('titleByUrl の内容が既存 mark に補完され、変更有りで true を返す', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', updatedAt: DateTime.utc(2026, 1, 1)),
      });

      final changed = container
          .read(marksProvider.notifier)
          .applyTitles({'https://a.example/': 'Resolved Title'});

      expect(changed, isTrue);
      expect(container.read(marksProvider)['https://a.example/']!.title, 'Resolved Title');
    });

    test('スナップショットに無い URL の mark には影響せず false を返す（§X2 回帰）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', updatedAt: DateTime.utc(2026, 1, 1)),
      });

      final changed = container
          .read(marksProvider.notifier)
          .applyTitles({'https://not-tracked.example/': 'X'});

      expect(changed, isFalse);
      expect(container.read(marksProvider)['https://a.example/']!.title, isNull);
      expect(container.read(marksProvider).containsKey('https://not-tracked.example/'), isFalse);
    });

    test('mergeFromServer で新規追加された mark にも直後の applyTitles で補完できる'
        '（§X2: 呼び出し順が pull と同じであることの回帰テスト）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // pullBookmarks と同じ順序: 先に mergeFromServer、その後 applyTitles。
      container.read(marksProvider.notifier).mergeFromServer([
        _mark('https://okbnetplaza.com/w', updatedAt: DateTime.utc(2026, 1, 1)),
      ]);
      final changed = container
          .read(marksProvider.notifier)
          .applyTitles({'https://okbnetplaza.com/w': 'スーパーOKダイレクト'});

      expect(changed, isTrue);
      expect(
        container.read(marksProvider)['https://okbnetplaza.com/w']!.title,
        'スーパーOKダイレクト',
      );
    });
  });

  group('snapshotTitleByUrlProvider', () {
    test('flat の title から URL→タイトルの Map を作る', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(snapshotProvider.notifier).setAll(null, const [
        FlatBookmark(
          url: 'https://a.example/',
          title: 'A サイト',
          rootKey: 'bookmark_bar',
          indexPath: [0],
          haystack: 'a サイト\nhttps://a.example/',
        ),
      ]);

      final titles = container.read(snapshotTitleByUrlProvider);
      expect(titles['https://a.example/'], 'A サイト');
    });

    test('空タイトルは除外される', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(snapshotProvider.notifier).setAll(null, const [
        FlatBookmark(
          url: 'https://b.example/',
          title: '',
          rootKey: 'bookmark_bar',
          indexPath: [0],
          haystack: '\nhttps://b.example/',
        ),
      ]);

      final titles = container.read(snapshotTitleByUrlProvider);
      expect(titles.containsKey('https://b.example/'), isFalse);
    });

    test('重複 URL は先勝ち', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(snapshotProvider.notifier).setAll(null, const [
        FlatBookmark(
          url: 'https://c.example/',
          title: '先勝ちタイトル',
          rootKey: 'bookmark_bar',
          indexPath: [0],
          haystack: '先勝ちタイトル\nhttps://c.example/',
        ),
        FlatBookmark(
          url: 'https://c.example/',
          title: '後勝ちにならない',
          rootKey: 'other',
          indexPath: [1],
          haystack: '後勝ちにならない\nhttps://c.example/',
        ),
      ]);

      final titles = container.read(snapshotTitleByUrlProvider);
      expect(titles['https://c.example/'], '先勝ちタイトル');
    });
  });

  group('PendingNotifier', () {
    test('enqueueOpen は2000件を超えたら古い方から破棄する', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);

      for (var i = 0; i < 2005; i++) {
        notifier.enqueueOpen(PendingOpen(
          eventId: 'e$i',
          url: 'https://a.example/',
          openedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
        ));
      }

      final opens = container.read(pendingProvider).opens;
      expect(opens, hasLength(2000));
      // 最初の5件（e0..e4）が破棄され、e5 以降が残る。
      expect(opens.first.eventId, 'e5');
      expect(opens.last.eventId, 'e2004');
    });

    test('enqueueStar は ON→OFF→ON が1件に潰れる', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);

      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: true, changedAt: DateTime.utc(2026, 1, 1)));
      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: false, changedAt: DateTime.utc(2026, 1, 2)));
      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: true, changedAt: DateTime.utc(2026, 1, 3)));

      final stars = container.read(pendingProvider).stars;
      expect(stars, hasLength(1));
      expect(stars['https://a.example/']!.starred, isTrue);
      expect(stars['https://a.example/']!.changedAt, DateTime.utc(2026, 1, 3));
    });

    test('removeOpens は指定した event_id のみ取り除く', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);

      notifier.enqueueOpen(PendingOpen(eventId: 'e1', url: 'https://a.example/', openedAt: DateTime.utc(2026, 1, 1)));
      notifier.enqueueOpen(PendingOpen(eventId: 'e2', url: 'https://b.example/', openedAt: DateTime.utc(2026, 1, 2)));

      notifier.removeOpens({'e1'});

      final opens = container.read(pendingProvider).opens;
      expect(opens, hasLength(1));
      expect(opens.single.eventId, 'e2');
    });

    test('removeStarIfUnchanged は送信後にユーザーが変更していなければ取り除く', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);
      final sentAt = DateTime.utc(2026, 1, 1);

      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: true, changedAt: sentAt));
      notifier.removeStarIfUnchanged('https://a.example/', sentAt);

      expect(container.read(pendingProvider).stars.containsKey('https://a.example/'), isFalse);
    });

    test('removeStarIfUnchanged は送信後にさらに変更されていたら残す', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);
      final sentAt = DateTime.utc(2026, 1, 1);
      final laterAt = DateTime.utc(2026, 1, 2);

      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: true, changedAt: sentAt));
      // flush 送信中にユーザーがさらにタップした想定。
      notifier.enqueueStar(PendingStar(url: 'https://a.example/', starred: false, changedAt: laterAt));

      notifier.removeStarIfUnchanged('https://a.example/', sentAt);

      final stars = container.read(pendingProvider).stars;
      expect(stars.containsKey('https://a.example/'), isTrue);
      expect(stars['https://a.example/']!.starred, isFalse);
    });
  });

  group('effectiveMarksProvider（オーバーレイ方式）', () {
    test('pending が空なら確定層をそのまま返す', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark('https://a.example/', openCount: 1, updatedAt: DateTime.utc(2026, 1, 1)),
      });

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://a.example/']!.openCount, 1);
    });

    test('pending の open が確定層に replay され openCount が増える', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark(
          'https://a.example/',
          openCount: 1,
          score: 1.0,
          scoreAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      });

      container.read(pendingProvider.notifier).enqueueOpen(PendingOpen(
            eventId: 'e1',
            url: 'https://a.example/',
            openedAt: DateTime.utc(2026, 1, 2),
          ));

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://a.example/']!.openCount, 2);
      // 確定層自体は変化しない（オーバーレイは読み出し時にのみ計算される）。
      expect(container.read(marksProvider)['https://a.example/']!.openCount, 1);
    });

    test('確定層に存在しない URL でも pending の open だけで行が生成される', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);

      container.read(pendingProvider.notifier).enqueueOpen(PendingOpen(
            eventId: 'e1',
            url: 'https://new.example/',
            openedAt: DateTime.utc(2026, 1, 1),
          ));

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://new.example/']!.openCount, 1);
      expect(effective['https://new.example/']!.score, 1.0);
    });

    test('複数の pending open は時刻順に replay される（順序が結果に影響しない）', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);
      final notifier = container.read(pendingProvider.notifier);

      // わざと時刻の逆順で積む。
      notifier.enqueueOpen(PendingOpen(eventId: 'e2', url: 'https://a.example/', openedAt: DateTime.utc(2026, 1, 10)));
      notifier.enqueueOpen(PendingOpen(eventId: 'e1', url: 'https://a.example/', openedAt: DateTime.utc(2026, 1, 1)));

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://a.example/']!.openCount, 2);
      expect(effective['https://a.example/']!.lastOpenedAt, DateTime.utc(2026, 1, 10));
    });

    test('pending の star は確定層の starred_at を上書きしない（初回のみ確定）', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);
      final firstStarredAt = DateTime.utc(2026, 1, 1);

      container.read(marksProvider.notifier).setAll({
        'https://a.example/': _mark(
          'https://a.example/',
          starred: true,
          starredAt: firstStarredAt,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      });

      // OFF→ON のトグルを保留に積んでも starred_at は初回の値のまま。
      container.read(pendingProvider.notifier).enqueueStar(
            PendingStar(url: 'https://a.example/', starred: false, changedAt: DateTime.utc(2026, 1, 5)),
          );

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://a.example/']!.starred, isFalse);
      expect(effective['https://a.example/']!.starredAt, firstStarredAt);
    });

    test('確定層に無い URL を新規に★した場合は pending の changedAt が starred_at になる', () async {
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(await _testPrefs())],
      );
      addTearDown(container.dispose);
      final changedAt = DateTime.utc(2026, 1, 1);

      container.read(pendingProvider.notifier).enqueueStar(
            PendingStar(url: 'https://new.example/', starred: true, changedAt: changedAt),
          );

      final effective = container.read(effectiveMarksProvider);
      expect(effective['https://new.example/']!.starred, isTrue);
      expect(effective['https://new.example/']!.starredAt, changedAt);
    });
  });
}
