import 'dart:io';

import '../models/mark.dart';
import 'json_file.dart';

/// `marks.json` の読み書き。**確定層**（サーバーが返したマークのみ）。
/// 楽観更新の結果はここに書かない（pending_store.dart 側の役目）。
/// キーは URL。
class MarksStore {
  MarksStore(Directory dir) : _jsonFile = JsonFile(File('${dir.path}/marks.json'));

  final JsonFile _jsonFile;

  Future<Map<String, Mark>> load() async {
    final json = await _jsonFile.readMap();
    if (json == null) return {};
    final marksJson = json['marks'];
    if (marksJson is! Map<String, dynamic>) return {};
    final result = <String, Mark>{};
    for (final entry in marksJson.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic>) {
        try {
          result[entry.key] = _markFromStoredJson(v);
        } catch (_) {
          // 1件の破損で全体を捨てない。
        }
      }
    }
    return result;
  }

  Future<void> save(Map<String, Mark> marks) => _jsonFile.writeMap({
        'version': 1,
        'marks': {for (final e in marks.entries) e.key: e.value.toJson()},
      });

  Future<void> clear() => _jsonFile.delete();

  static Mark _markFromStoredJson(Map<String, dynamic> json) => Mark(
        url: json['url'] as String,
        starred: (json['starred'] as bool?) ?? false,
        starredAt: _date(json['starred_at']),
        openCount: (json['open_count'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        scoreAt: _date(json['score_at']),
        lastOpenedAt: _date(json['last_opened_at']),
        updatedAt: _date(json['updated_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        title: json['title'] as String?,
      );

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
}
