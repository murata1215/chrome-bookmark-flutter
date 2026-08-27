import 'dart:io';

import '../models/bookmark_snapshot.dart';
import 'json_file.dart';

/// `snapshot.json` の読み書き。直前世代を `.bak` に残し、パース失敗時は
/// そちらへフォールバックする（tree_hash はここでは検証しない。空/破損なら
/// null を返すだけにして、呼び出し側が「送らずに再取得」を判断する）。
class SnapshotStore {
  SnapshotStore(Directory dir)
      : _jsonFile = JsonFile(File('${dir.path}/snapshot.json'), keepBackup: true);

  final JsonFile _jsonFile;

  Future<BookmarkSnapshot?> load() async {
    final json = await _jsonFile.readMap();
    if (json == null) return null;
    try {
      return BookmarkSnapshot.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(BookmarkSnapshot snapshot) => _jsonFile.writeMap(snapshot.toJson());

  Future<void> clear() => _jsonFile.delete();
}
