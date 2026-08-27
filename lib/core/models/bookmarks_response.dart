import 'mark.dart';

/// GET /bookmarks の応答。
class BookmarksResponse {
  final String treeHash;
  final Map<String, dynamic>? roots; // null なら手元の tree_hash と一致（未変更）
  final DateTime snapshotUpdatedAt;
  final List<Mark> marks;
  final DateTime serverTime;
  final bool hasMore;

  const BookmarksResponse({
    required this.treeHash,
    required this.roots,
    required this.snapshotUpdatedAt,
    required this.marks,
    required this.serverTime,
    required this.hasMore,
  });

  factory BookmarksResponse.fromJson(Map<String, dynamic> json) {
    final marksJson = (json['marks'] as List<dynamic>? ?? const []);
    return BookmarksResponse(
      treeHash: (json['tree_hash'] as String?) ?? '',
      roots: json['roots'] as Map<String, dynamic>?,
      snapshotUpdatedAt:
          DateTime.tryParse((json['snapshot_updated_at'] as String?) ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      marks: marksJson
          .whereType<Map<String, dynamic>>()
          .map((m) => Mark.fromJson(m))
          .toList(),
      serverTime: DateTime.tryParse((json['server_time'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      hasMore: (json['has_more'] as bool?) ?? false,
    );
  }
}

/// POST /marks/open の応答。
class OpenBatchResponse {
  final int accepted;
  final int duplicates;
  final List<Mark> marks;
  final DateTime? serverTime;

  const OpenBatchResponse({
    required this.accepted,
    required this.duplicates,
    required this.marks,
    required this.serverTime,
  });

  factory OpenBatchResponse.fromJson(Map<String, dynamic> json) {
    final marksJson = (json['marks'] as List<dynamic>? ?? const []);
    return OpenBatchResponse(
      accepted: (json['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
      marks: marksJson
          .whereType<Map<String, dynamic>>()
          .map((m) => Mark.fromJson(m))
          .toList(),
      serverTime: json['server_time'] is String
          ? DateTime.tryParse(json['server_time'] as String)?.toUtc()
          : null,
    );
  }
}

/// POST /pairing/claim の応答。
class PairingClaimResponse {
  final String deviceToken;
  final String email;

  const PairingClaimResponse({required this.deviceToken, required this.email});

  factory PairingClaimResponse.fromJson(Map<String, dynamic> json) => PairingClaimResponse(
        deviceToken: json['device_token'] as String,
        email: (json['email'] as String?) ?? '',
      );
}

/// PUT /marks/star の応答。応答形が `{"mark": {...}, "server_time": "..."}` と
/// フラット（トップレベルに url 等が直接ある）のどちらでも読めるようにしておく
/// （§0-5 でサーバーが `starred_at`・`server_time` を追加予定だが、正確な
/// ネスト形はデプロイまで確定できないため）。
class StarResponse {
  final Mark mark;
  final DateTime? serverTime;

  const StarResponse({required this.mark, required this.serverTime});

  factory StarResponse.fromJson(Map<String, dynamic> json) {
    final markJson = json['mark'] is Map<String, dynamic>
        ? json['mark'] as Map<String, dynamic>
        : json;
    return StarResponse(
      mark: Mark.fromJson(markJson),
      serverTime: json['server_time'] is String
          ? DateTime.tryParse(json['server_time'] as String)?.toUtc()
          : null,
    );
  }
}
