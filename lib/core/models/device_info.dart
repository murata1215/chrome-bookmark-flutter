/// GET /device の応答（サーバー側追加予定。404 の間はフォールバック値を使う）。
class DeviceInfoResponse {
  final String name;
  final String platform;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String email;
  final DateTime? snapshotUpdatedAt;
  final int? marksCount;

  const DeviceInfoResponse({
    required this.name,
    required this.platform,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.email,
    required this.snapshotUpdatedAt,
    required this.marksCount,
  });

  factory DeviceInfoResponse.fromJson(Map<String, dynamic> json) => DeviceInfoResponse(
        name: (json['name'] as String?) ?? '',
        platform: (json['platform'] as String?) ?? '',
        pairedAt: _date(json['paired_at']),
        lastSeenAt: _date(json['last_seen_at']),
        email: (json['email'] as String?) ?? '',
        snapshotUpdatedAt: _date(json['snapshot_updated_at']),
        marksCount: (json['marks_count'] as num?)?.toInt(),
      );

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
}
