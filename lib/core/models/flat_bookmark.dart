import 'bookmark_node.dart';
import 'bookmark_snapshot.dart';

/// スナップショットを検索・一覧用に平坦化した1行。
class FlatBookmark {
  final String url;
  final String title;
  final String rootKey;
  final List<int> indexPath; // root 直下からの子インデックス列（フォルダを含む）
  final String haystack; // "${title}\n${url}" の小文字化

  const FlatBookmark({
    required this.url,
    required this.title,
    required this.rootKey,
    required this.indexPath,
    required this.haystack,
  });
}

/// スナップショットの平坦化結果。Isolate 内で構築して1回で main isolate に返す。
class FlattenResult {
  final List<FlatBookmark> flat;
  final Map<String, String> titleByUrl; // 先勝ち
  const FlattenResult({required this.flat, required this.titleByUrl});
}

FlattenResult flattenSnapshot(BookmarkSnapshot snapshot) {
  final flat = <FlatBookmark>[];
  final titleByUrl = <String, String>{};

  void walk(String rootKey, BookmarkNode node, List<int> path) {
    if (node is BookmarkFolder) {
      for (var i = 0; i < node.children.length; i++) {
        walk(rootKey, node.children[i], [...path, i]);
      }
    } else if (node is BookmarkUrl) {
      if (node.url.isEmpty) return;
      flat.add(FlatBookmark(
        url: node.url,
        title: node.title,
        rootKey: rootKey,
        indexPath: path,
        haystack: '${node.title}\n${node.url}'.toLowerCase(),
      ));
      titleByUrl.putIfAbsent(node.url, () => node.title);
    }
  }

  for (final entry in snapshot.roots.entries) {
    walk(entry.key, entry.value, const []);
  }

  return FlattenResult(flat: flat, titleByUrl: titleByUrl);
}

/// Isolate.run に渡す入力（JSON文字列 → パース → 平坦化まで isolate 内で完結させる）。
class ParseSnapshotInput {
  final String jsonBody; // GET /bookmarks の生レスポンス、または snapshot.json の内容
  const ParseSnapshotInput(this.jsonBody);
}

class ParseSnapshotOutput {
  final BookmarkSnapshot snapshot;
  final List<FlatBookmark> flat;
  final Map<String, String> titleByUrl;
  const ParseSnapshotOutput({
    required this.snapshot,
    required this.flat,
    required this.titleByUrl,
  });
}
