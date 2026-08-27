import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/bookmark_snapshot.dart';
import '../models/flat_bookmark.dart';
import '../models/mark.dart';
import '../models/pending.dart';
import 'marks_store.dart';
import 'pending_store.dart';
import 'snapshot_store.dart';

/// 起動時に読み込む3ファイルと、それらから導出される索引をまとめて返す。
class LocalStoreBundle {
  final BookmarkSnapshot? snapshot;
  final List<FlatBookmark> flat; // snapshot が無ければ空
  final Map<String, String> titleByUrl; // snapshot 由来
  final Map<String, Mark> marks;
  final PendingQueue pending;

  const LocalStoreBundle({
    required this.snapshot,
    required this.flat,
    required this.titleByUrl,
    required this.marks,
    required this.pending,
  });
}

/// `snapshot.json` / `marks.json` / `pending.json` の3ストアを束ね、
/// 起動時の読み込みとツリーのパース・平坦化（Isolate）を行う。
///
/// §7 の 500ms 目標のため、★・頻度タブは snapshot 抜きで描けるように
/// `marks.json` と `titleByUrl`（snapshot 由来）だけで賄う設計。
/// ツリータブと検索だけが `flat`/`snapshot` を必要とする。
class LocalStore {
  LocalStore(Directory dir)
      : snapshotStore = SnapshotStore(dir),
        marksStore = MarksStore(dir),
        pendingStore = PendingStore(dir);

  final SnapshotStore snapshotStore;
  final MarksStore marksStore;
  final PendingStore pendingStore;

  /// 起動時の一括読み込み。snapshot の平坦化のみ Isolate 上で行う
  /// （デコード済みノードをディープコピーで main isolate に返すコストを避けるため、
  /// 実際に重いのは `GET /bookmarks` 受信直後の [parseSnapshotJson] の方。
  /// こちらは既にディスクから読んだ小さめの snapshot を平坦化するだけ）。
  Future<LocalStoreBundle> loadAll() async {
    final marksFuture = marksStore.load();
    final pendingFuture = pendingStore.load();
    final snapshot = await snapshotStore.load();

    List<FlatBookmark> flat = const [];
    Map<String, String> titleByUrl = const {};
    if (snapshot != null) {
      final result = await Isolate.run(() => flattenSnapshot(snapshot));
      flat = result.flat;
      titleByUrl = result.titleByUrl;
    }

    return LocalStoreBundle(
      snapshot: snapshot,
      flat: flat,
      titleByUrl: titleByUrl,
      marks: await marksFuture,
      pending: await pendingFuture,
    );
  }

  /// `GET /bookmarks` の生 JSON 文字列（`tree_hash`/`roots`/`snapshot_updated_at`
  /// を含む）から snapshot のパースと平坦化までを Isolate 内で完結させる（D-3）。
  /// `roots` が null（= tree_hash 一致で本文が省略された）場合は呼び出し側で
  /// この関数を呼ばず、ローカルの snapshot をそのまま使い続けること。
  static Future<ParseSnapshotOutput> parseSnapshotJson(String jsonBody) {
    return Isolate.run(() => _parseSnapshotJsonSync(jsonBody));
  }

  Future<void> clearAll() async {
    await Future.wait([
      snapshotStore.clear(),
      marksStore.clear(),
      pendingStore.clear(),
    ]);
  }
}

ParseSnapshotOutput _parseSnapshotJsonSync(String jsonBody) {
  final json = jsonDecode(jsonBody) as Map<String, dynamic>;
  final snapshot = BookmarkSnapshot.fromJson(json);
  final flattened = flattenSnapshot(snapshot);
  return ParseSnapshotOutput(
    snapshot: snapshot,
    flat: flattened.flat,
    titleByUrl: flattened.titleByUrl,
  );
}
