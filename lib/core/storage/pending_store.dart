import 'dart:io';

import '../models/pending.dart';
import 'json_file.dart';

/// `pending.json` の読み書き。**保留層**（未送信の open イベント・★変更）。
class PendingStore {
  PendingStore(Directory dir) : _jsonFile = JsonFile(File('${dir.path}/pending.json'));

  final JsonFile _jsonFile;

  Future<PendingQueue> load() async {
    final json = await _jsonFile.readMap();
    if (json == null) return PendingQueue.empty;
    try {
      return PendingQueue.fromJson(json);
    } catch (_) {
      // 壊れた JSON は例外にせず空キューとして扱う（未送信分は失われるが、
      // ファイル全体が読めないよりはアプリを止めない方を優先する）。
      return PendingQueue.empty;
    }
  }

  Future<void> save(PendingQueue queue) => _jsonFile.writeMap(queue.toJson());

  Future<void> clear() => _jsonFile.delete();
}
