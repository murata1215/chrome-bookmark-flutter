import 'dart:math' as math;

/// §3.1 frecency（順序非依存版）。
///
/// サーバー実装（TS）は half_life をミリ秒で扱い、日数への丸め・整数除算は
/// 一切行わない（chrome-bookmark サーバーチームに確認済み）。
/// Dart 側は `Duration.inMicroseconds` を使うことで同じ精度を保つ。
const Duration kHalfLife = Duration(days: 30);

/// 「頻度」タブの表示閾値（§3.1）。
const double kFrequencyThreshold = 0.1;

/// 「頻度」タブの表示上限（§6.3）。
const int kFrequencyLimit = 50;

/// decay(Δ) = 0.5 ^ (Δ / half_life)。Δ が負（未来）の場合は 1.0 を返す
/// （呼び出し側で t>=T / t<T の分岐により符号は解決済みという前提）。
double decay(Duration delta) {
  if (delta.isNegative) return 1.0;
  final ratio = delta.inMicroseconds / kHalfLife.inMicroseconds;
  return math.pow(0.5, ratio).toDouble();
}

/// frecency の適用結果。
class FrecencyResult {
  final double score;
  final DateTime scoreAt;
  const FrecencyResult({required this.score, required this.scoreAt});
}

/// オープンイベント1件を適用する（到着順に依存しない・§3.1）。
///
/// - `scoreAt == null`（初回）: score = 1, score_at = t
/// - `t >= T`: score = score * decay(t - T) + 1 ; score_at = t
/// - `t < T`（遅れて届いた古いイベント）: score = score + decay(T - t) ; score_at は据え置き
FrecencyResult applyOpen({
  required double score,
  required DateTime? scoreAt,
  required DateTime openedAt,
}) {
  final t = openedAt.toUtc();
  if (scoreAt == null) {
    return FrecencyResult(score: 1.0, scoreAt: t);
  }
  final tAt = scoreAt.toUtc();
  if (!t.isBefore(tAt)) {
    // t >= T
    return FrecencyResult(
      score: score * decay(t.difference(tAt)) + 1.0,
      scoreAt: t,
    );
  }
  // t < T
  return FrecencyResult(
    score: score + decay(tAt.difference(t)),
    scoreAt: tAt,
  );
}

/// 表示時の実効値: effective = score * decay(now - score_at)
double effectiveScore({
  required double score,
  required DateTime? scoreAt,
  required DateTime now,
}) {
  if (scoreAt == null) return 0.0;
  return score * decay(now.toUtc().difference(scoreAt.toUtc()));
}

/// 頻度タブのソートキー。
///
/// log2(effective) = log2(score) + score_at/HL − now/HL
/// now/HL は全項目共通の定数項なので、rankKey 降順は effective 降順と完全に一致する。
/// これにより「今」に依存しない安定なソートキーとして扱える（再ソートは値変更時のみでよい）。
///
/// score <= 0（★のみでオープン実績が無い行）は呼び出し側で除外すること
/// （log2(0) = -infinity になるため）。
double rankKey({required double score, required DateTime scoreAt}) {
  final scoreAtMs = scoreAt.toUtc().millisecondsSinceEpoch.toDouble();
  final halfLifeMs = kHalfLife.inMilliseconds.toDouble();
  return _log2(score) + scoreAtMs / halfLifeMs;
}

double _log2(double x) => math.log(x) / math.ln2;

/// タップ時刻がサーバー時刻より大きく先行している場合に丸める（§0-2・D-1）。
///
/// `frecency.dart` 自体（[applyOpen]）は意図的にクランプを行わない純関数のため
/// （クランプは同期層の責務・§3.1）、`applyOpen` を呼ぶ前に必ずこれを通すこと。
/// - 閾値は `serverNow + 5分`（この範囲内なら実測どおり採用する）
/// - 丸め先は `serverNow` そのもの（`+5分` にはしない。サーバー側の実装・§0-2 と一致）
DateTime clampOpenedAt(DateTime openedAt, DateTime serverNow) {
  final t = openedAt.toUtc();
  final now = serverNow.toUtc();
  final threshold = now.add(const Duration(minutes: 5));
  return t.isAfter(threshold) ? now : t;
}
