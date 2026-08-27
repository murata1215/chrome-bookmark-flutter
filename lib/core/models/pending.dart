/// 未送信の open イベント。
class PendingOpen {
  final String eventId;
  final String url;
  final DateTime openedAt;

  const PendingOpen({required this.eventId, required this.url, required this.openedAt});

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'url': url,
        'opened_at': openedAt.toIso8601String(),
      };

  factory PendingOpen.fromJson(Map<String, dynamic> json) => PendingOpen(
        eventId: json['event_id'] as String,
        url: json['url'] as String,
        openedAt: DateTime.parse(json['opened_at'] as String).toUtc(),
      );
}

/// 未送信の ★ 変更（URL キーでの上書き。ON→OFF→ON は1件に潰れる）。
class PendingStar {
  final String url;
  final bool starred;
  final DateTime changedAt;

  const PendingStar({required this.url, required this.starred, required this.changedAt});

  Map<String, dynamic> toJson() => {
        'url': url,
        'starred': starred,
        'changed_at': changedAt.toIso8601String(),
      };

  factory PendingStar.fromJson(Map<String, dynamic> json) => PendingStar(
        url: json['url'] as String,
        starred: json['starred'] as bool,
        changedAt: DateTime.parse(json['changed_at'] as String).toUtc(),
      );
}

class PendingQueue {
  final List<PendingOpen> opens;
  final Map<String, PendingStar> stars; // key: url

  const PendingQueue({required this.opens, required this.stars});

  static const empty = PendingQueue(opens: [], stars: {});

  Map<String, dynamic> toJson() => {
        'version': 1,
        'opens': opens.map((e) => e.toJson()).toList(),
        'stars': {for (final e in stars.entries) e.key: e.value.toJson()},
      };

  factory PendingQueue.fromJson(Map<String, dynamic> json) {
    final opensJson = (json['opens'] as List<dynamic>? ?? const []);
    final starsJson = (json['stars'] as Map<String, dynamic>? ?? const {});
    return PendingQueue(
      opens: opensJson
          .whereType<Map<String, dynamic>>()
          .map(PendingOpen.fromJson)
          .toList(),
      stars: {
        for (final e in starsJson.entries)
          if (e.value is Map<String, dynamic>)
            e.key: PendingStar.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  bool get isEmpty => opens.isEmpty && stars.isEmpty;
}
