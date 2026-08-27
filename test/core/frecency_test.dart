import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chrome_bookmark_flutter/core/frecency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decay', () {
    test('半減期ちょうど30日で 0.5 になる', () {
      expect(decay(const Duration(days: 30)), closeTo(0.5, 1e-9));
    });

    test('Δ=0 では 1.0', () {
      expect(decay(Duration.zero), 1.0);
    });

    test('負の Δ（未来）では 1.0', () {
      expect(decay(const Duration(days: -10)), 1.0);
    });
  });

  group('applyOpen', () {
    test('初回オープンは score=1, score_at=openedAt', () {
      final t = DateTime.utc(2026, 1, 1);
      final r = applyOpen(score: 0, scoreAt: null, openedAt: t);
      expect(r.score, 1.0);
      expect(r.scoreAt, t);
    });

    test('t >= T のとき score_at は t に進む', () {
      final tAt = DateTime.utc(2026, 1, 1);
      final t = DateTime.utc(2026, 1, 15);
      final r = applyOpen(score: 2.0, scoreAt: tAt, openedAt: t);
      expect(r.scoreAt, t);
      final expectedScore = 2.0 * decay(t.difference(tAt)) + 1.0;
      expect(r.score, closeTo(expectedScore, 1e-9));
    });

    test('t == T（同時刻）は t >= T 側で処理される', () {
      final t = DateTime.utc(2026, 1, 1, 12, 0, 0, 0, 1); // マイクロ秒まで同一
      final r = applyOpen(score: 1.0, scoreAt: t, openedAt: t);
      expect(r.scoreAt, t);
      expect(r.score, closeTo(2.0, 1e-9)); // decay(0)=1 なので 1*1+1=2
    });

    test('t < T（遅れて届いた古いイベント）は score_at を据え置く', () {
      final tAt = DateTime.utc(2026, 1, 15);
      final t = DateTime.utc(2026, 1, 1); // tAt より過去
      final r = applyOpen(score: 2.0, scoreAt: tAt, openedAt: t);
      expect(r.scoreAt, tAt); // 据え置き
      final expectedScore = 2.0 + decay(tAt.difference(t));
      expect(r.score, closeTo(expectedScore, 1e-9));
    });

    test('順列不変性: 適用順序を変えても最終スコアは一致する（5順列）', () {
      final base = DateTime.utc(2026, 1, 1);
      final events = [
        base,
        base.add(const Duration(days: 3)),
        base.add(const Duration(days: 10)),
        base.add(const Duration(days: 1)),
        base.add(const Duration(days: 25)),
      ];

      double applyAll(List<DateTime> order) {
        double score = 0;
        DateTime? scoreAt;
        for (final t in order) {
          final r = applyOpen(score: score, scoreAt: scoreAt, openedAt: t);
          score = r.score;
          scoreAt = r.scoreAt;
        }
        return score;
      }

      final canonical = applyAll(events);
      final random = Random(42);
      for (var i = 0; i < 5; i++) {
        final shuffled = [...events]..shuffle(random);
        expect(applyAll(shuffled), closeTo(canonical, 1e-9));
      }
    });

    test('未来の openedAt は呼び出し側でクランプする前提（frecency 自体はクランプしない）', () {
      // frecency.dart はクランプを行わない純関数。クランプは sync 層の責務（§3.1・§0-2）。
      final tAt = DateTime.utc(2026, 1, 1);
      final farFuture = DateTime.utc(2100, 1, 1);
      final r = applyOpen(score: 1.0, scoreAt: tAt, openedAt: farFuture);
      expect(r.scoreAt, farFuture);
    });
  });

  group('effectiveScore', () {
    test('scoreAt が null なら 0', () {
      expect(effectiveScore(score: 5, scoreAt: null, now: DateTime.now()), 0.0);
    });

    test('半減期経過後は score のちょうど半分', () {
      final scoreAt = DateTime.utc(2026, 1, 1);
      final now = scoreAt.add(const Duration(days: 30));
      expect(effectiveScore(score: 4.0, scoreAt: scoreAt, now: now), closeTo(2.0, 1e-9));
    });
  });

  group('rankKey', () {
    test('rankKey 降順は effective 降順と一致する（now に依存しない）', () {
      final now = DateTime.utc(2026, 6, 1);
      final items = [
        (score: 1.0, scoreAt: DateTime.utc(2026, 1, 1)),
        (score: 5.0, scoreAt: DateTime.utc(2026, 3, 1)),
        (score: 0.5, scoreAt: DateTime.utc(2026, 5, 20)),
        (score: 20.0, scoreAt: DateTime.utc(2025, 12, 1)),
      ];

      final byRankKey = [...items]
        ..sort((a, b) => rankKey(score: b.score, scoreAt: b.scoreAt)
            .compareTo(rankKey(score: a.score, scoreAt: a.scoreAt)));
      final byEffective = [...items]
        ..sort((a, b) => effectiveScore(score: b.score, scoreAt: b.scoreAt, now: now)
            .compareTo(effectiveScore(score: a.score, scoreAt: a.scoreAt, now: now)));

      expect(byRankKey, orderedEquals(byEffective));
    });
  });

  group('clampOpenedAt', () {
    test('serverNow + 5分以内ならそのまま', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final t = now.add(const Duration(minutes: 4, seconds: 59));
      expect(clampOpenedAt(t, now), t);
    });

    test('serverNow + 5分を超えたら serverNow に丸める', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final t = now.add(const Duration(minutes: 10));
      expect(clampOpenedAt(t, now), now);
    });

    test('過去の openedAt はそのまま', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final t = now.subtract(const Duration(days: 5));
      expect(clampOpenedAt(t, now), t);
    });
  });

  group('golden vectors（サーバー提供）', () {
    final file = File('test/fixtures/frecency_golden_vectors.json');

    test('half_life_ms が kHalfLife と一致し、全ケースを 1e-9 精度で通す', () {
      if (!file.existsSync()) {
        // サーバーからの受領待ち（プラン §0-2 参照）。届き次第
        // test/fixtures/frecency_golden_vectors.json に配置すればこのテストが有効になる。
        markTestSkipped('frecency_golden_vectors.json が未配置のためスキップ');
        return;
      }

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final halfLifeMs = (json['half_life_ms'] as num).toInt();
      expect(halfLifeMs, kHalfLife.inMilliseconds, reason: '半減期の単位取り違え検出');

      final cases = (json['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final c in cases) {
        final name = c['name'] as String? ?? '(no name)';
        final now = DateTime.parse(c['now'] as String).toUtc();
        final existing = c['existing'] as Map<String, dynamic>?;
        double score = (existing?['score'] as num?)?.toDouble() ?? 0;
        DateTime? scoreAt =
            existing?['score_at'] != null ? DateTime.parse(existing!['score_at'] as String).toUtc() : null;
        int openCount = (existing?['open_count'] as num?)?.toInt() ?? 0;
        // フィクスチャの `existing` は score_at までしか持たないが、この生成方式
        // （1件の既存行は必ずその score_at 時点の1オープンで作られている）では
        // クランプ前の last_opened_at は score_at と一致する（サーバー担当確認済みの
        // GREATEST(marks.last_opened_at, excluded.last_opened_at) 挙動と整合）。
        DateTime? lastOpenedAt = scoreAt;

        final events = (c['events'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final e in events) {
          final rawOpenedAt = DateTime.parse(e['opened_at'] as String).toUtc();
          // クランプは sync 層の責務（frecency.dart 自体は行わない）なので、
          // applyOpen を呼ぶ前に必ず通す（§0-2・D-1）。
          final openedAt = clampOpenedAt(rawOpenedAt, now);
          final r = applyOpen(score: score, scoreAt: scoreAt, openedAt: openedAt);
          score = r.score;
          scoreAt = r.scoreAt;
          openCount += 1;
          final prevLastOpened = lastOpenedAt;
          lastOpenedAt = (prevLastOpened == null || prevLastOpened.isBefore(openedAt))
              ? openedAt
              : prevLastOpened;
        }

        final expected = c['expected'] as Map<String, dynamic>;
        expect(score, closeTo((expected['score'] as num).toDouble(), 1e-9), reason: 'case: $name (score)');
        if (expected['score_at'] != null) {
          expect(scoreAt, DateTime.parse(expected['score_at'] as String).toUtc(),
              reason: 'case: $name (score_at)');
        }
        if (expected['open_count'] != null) {
          expect(openCount, (expected['open_count'] as num).toInt(), reason: 'case: $name (open_count)');
        }
        if (expected['last_opened_at'] != null) {
          expect(lastOpenedAt, DateTime.parse(expected['last_opened_at'] as String).toUtc(),
              reason: 'case: $name (last_opened_at)');
        }
        if (expected['effective_at_now'] != null) {
          final effective = effectiveScore(score: score, scoreAt: scoreAt, now: now);
          expect(effective, closeTo((expected['effective_at_now'] as num).toDouble(), 1e-9),
              reason: 'case: $name (effective_at_now)');
        }
      }
    });
  });
}
