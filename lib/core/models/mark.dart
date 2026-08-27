import '../frecency.dart';

/// URL 単位の付加データ。サーバー由来のフィールドと、クライアントのみが持つ
/// `title`（スナップショットから補完。§3 の「スナップショットに無いURLの
/// マークは消さない」仕様により、サーバー応答には title が含まれないため）。
class Mark {
  final String url;
  final bool starred;
  final DateTime? starredAt;
  final int openCount;
  final double score;
  final DateTime? scoreAt;
  final DateTime? lastOpenedAt;
  final DateTime updatedAt;
  final String? title; // クライアント専用

  const Mark({
    required this.url,
    required this.starred,
    required this.starredAt,
    required this.openCount,
    required this.score,
    required this.scoreAt,
    required this.lastOpenedAt,
    required this.updatedAt,
    this.title,
  });

  factory Mark.empty(String url) => Mark(
        url: url,
        starred: false,
        starredAt: null,
        openCount: 0,
        score: 0,
        scoreAt: null,
        lastOpenedAt: null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  factory Mark.fromJson(Map<String, dynamic> json, {String? title}) => Mark(
        url: json['url'] as String,
        starred: (json['starred'] as bool?) ?? false,
        starredAt: _parseDate(json['starred_at']),
        openCount: (json['open_count'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        scoreAt: _parseDate(json['score_at']),
        lastOpenedAt: _parseDate(json['last_opened_at']),
        updatedAt: _parseDate(json['updated_at']) ?? DateTime.now().toUtc(),
        title: title,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'starred': starred,
        'starred_at': starredAt?.toIso8601String(),
        'open_count': openCount,
        'score': score,
        'score_at': scoreAt?.toIso8601String(),
        'last_opened_at': lastOpenedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'title': title,
      };

  static DateTime? _parseDate(Object? v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
    return null;
  }

  Mark copyWith({
    bool? starred,
    DateTime? starredAt,
    bool starredAtToNull = false,
    int? openCount,
    double? score,
    DateTime? scoreAt,
    DateTime? lastOpenedAt,
    DateTime? updatedAt,
    String? title,
  }) {
    return Mark(
      url: url,
      starred: starred ?? this.starred,
      starredAt: starredAtToNull ? null : (starredAt ?? this.starredAt),
      openCount: openCount ?? this.openCount,
      score: score ?? this.score,
      scoreAt: scoreAt ?? this.scoreAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
    );
  }

  Mark withTitle(String? newTitle) =>
      newTitle == null ? this : copyWith(title: newTitle);

  /// ローカルでの楽観的なオープン適用（§3.1・§6.4）。
  Mark applyLocalOpen(DateTime openedAt) {
    final r = applyOpen(score: score, scoreAt: scoreAt, openedAt: openedAt);
    final newLastOpened = (lastOpenedAt == null || lastOpenedAt!.isBefore(openedAt))
        ? openedAt
        : lastOpenedAt;
    return copyWith(
      score: r.score,
      scoreAt: r.scoreAt,
      openCount: openCount + 1,
      lastOpenedAt: newLastOpened,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  double effective(DateTime now) =>
      effectiveScore(score: score, scoreAt: scoreAt, now: now);
}
