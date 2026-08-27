import 'bookmark_node.dart';
import 'bookmark_snapshot.dart';

/// 兄弟内でのタイトル出現順を含むフォルダの同定情報。
/// §4.3 の正規化ノードには id が無く、スナップショットは丸ごと置き換わるため、
/// index path だけでは並べ替えに弱く、title だけでは同名兄弟フォルダで曖昧になる。
/// 両方を持たせ、フォールバックしながら解決する。
class FolderPathSegment {
  final String title;
  final int occurrence; // 同名兄弟の中での 0 始まり出現順

  const FolderPathSegment({required this.title, required this.occurrence});

  Map<String, dynamic> toJson() => {'title': title, 'occurrence': occurrence};

  factory FolderPathSegment.fromJson(Map<String, dynamic> json) =>
      FolderPathSegment(
        title: (json['title'] as String?) ?? '',
        occurrence: (json['occurrence'] as num?)?.toInt() ?? 0,
      );
}

class FolderPath {
  final String rootKey;
  final List<FolderPathSegment> segments;

  const FolderPath({required this.rootKey, required this.segments});

  static const FolderPath root = FolderPath(rootKey: 'bookmark_bar', segments: []);

  Map<String, dynamic> toJson() => {
        'root': rootKey,
        'path': segments.map((s) => s.toJson()).toList(),
      };

  factory FolderPath.fromJson(Map<String, dynamic> json) {
    final segs = (json['path'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FolderPathSegment.fromJson)
        .toList();
    return FolderPath(rootKey: (json['root'] as String?) ?? 'bookmark_bar', segments: segs);
  }

  FolderPath appending(String title, int occurrence) => FolderPath(
        rootKey: rootKey,
        segments: [...segments, FolderPathSegment(title: title, occurrence: occurrence)],
      );

  FolderPath get parent => segments.isEmpty
      ? this
      : FolderPath(rootKey: rootKey, segments: segments.sublist(0, segments.length - 1));
}

/// 解決結果: 実際に辿り着けたフォルダとその index path・タイトルパンくず。
class ResolvedFolder {
  final BookmarkFolder folder;
  final List<int> indexPath;
  final FolderPath path;
  final bool exact; // 保存されていたパスと完全一致したか（浅くなっていないか）

  const ResolvedFolder({
    required this.folder,
    required this.indexPath,
    required this.path,
    required this.exact,
  });
}

/// 保存された FolderPath をスナップショットに対して解決する。
/// 各階層で: ①タイトル+出現順が一致 → それ、②タイトルのみ一致（最初の1つ）→ それ、
/// ③一致無し → そこで停止し、辿れた最深フォルダを返す（根まで戻さない）。
ResolvedFolder resolveFolderPath(BookmarkSnapshot snapshot, FolderPath saved) {
  final root = snapshot.roots[saved.rootKey] ?? snapshot.roots[kRootKeys.first];
  if (root == null) {
    // ルートが1つも無い異常系。空のダミーフォルダを返す。
    return ResolvedFolder(
      folder: const BookmarkFolder(title: '', dateAdded: 0, children: []),
      indexPath: const [],
      path: const FolderPath(rootKey: 'bookmark_bar', segments: []),
      exact: false,
    );
  }

  var current = root;
  var indexPath = <int>[];
  var resolvedSegments = <FolderPathSegment>[];
  var exact = true;

  for (final seg in saved.segments) {
    // 同名の folder 子を出現順に列挙
    final matches = <int>[];
    for (var i = 0; i < current.children.length; i++) {
      final c = current.children[i];
      if (c is BookmarkFolder && c.title == seg.title) matches.add(i);
    }
    if (matches.isEmpty) {
      exact = false;
      break;
    }
    final chosenIdx = seg.occurrence < matches.length ? matches[seg.occurrence] : matches.first;
    if (seg.occurrence >= matches.length) exact = false;
    final chosenOccurrence = matches.indexOf(chosenIdx);

    current = current.children[chosenIdx] as BookmarkFolder;
    indexPath = [...indexPath, chosenIdx];
    resolvedSegments = [
      ...resolvedSegments,
      FolderPathSegment(title: seg.title, occurrence: chosenOccurrence),
    ];
  }

  return ResolvedFolder(
    folder: current,
    indexPath: indexPath,
    path: FolderPath(rootKey: saved.rootKey, segments: resolvedSegments),
    exact: exact && resolvedSegments.length == saved.segments.length,
  );
}

/// 現在のフォルダから子フォルダへ降りる際、その子の FolderPathSegment を計算する
/// （同名兄弟の中での出現順を数える）。
FolderPathSegment segmentForChild(BookmarkFolder parent, int childIndex) {
  final child = parent.children[childIndex] as BookmarkFolder;
  var occurrence = 0;
  for (var i = 0; i < childIndex; i++) {
    final c = parent.children[i];
    if (c is BookmarkFolder && c.title == child.title) occurrence++;
  }
  return FolderPathSegment(title: child.title, occurrence: occurrence);
}
