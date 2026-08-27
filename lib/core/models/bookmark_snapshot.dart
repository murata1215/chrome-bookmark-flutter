import 'bookmark_node.dart';

const List<String> kRootKeys = ['bookmark_bar', 'other', 'mobile'];

String rootLabel(String key) => switch (key) {
      'bookmark_bar' => 'ブックマーク バー',
      'other' => 'その他のブックマーク',
      'mobile' => 'モバイルのブックマーク',
      _ => key,
    };

/// §4.3 のスナップショット。tree_hash はサーバー側だけが計算する
/// **不透明トークン**として扱う（アプリ側では再計算しない）。
class BookmarkSnapshot {
  final String treeHash;
  final Map<String, BookmarkFolder> roots; // key: bookmark_bar/other/mobile
  final DateTime updatedAt;

  const BookmarkSnapshot({
    required this.treeHash,
    required this.roots,
    required this.updatedAt,
  });

  factory BookmarkSnapshot.fromJson(Map<String, dynamic> json) {
    final rootsJson = (json['roots'] as Map<String, dynamic>? ?? const {});
    final roots = <String, BookmarkFolder>{};
    for (final key in kRootKeys) {
      final v = rootsJson[key];
      if (v is Map<String, dynamic>) {
        final node = BookmarkNode.fromJson(v);
        if (node is BookmarkFolder) roots[key] = node;
      }
    }
    return BookmarkSnapshot(
      treeHash: (json['tree_hash'] as String?) ?? '',
      roots: roots,
      updatedAt: DateTime.tryParse((json['snapshot_updated_at'] as String?) ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tree_hash': treeHash,
        'roots': {for (final e in roots.entries) e.key: e.value.toJson()},
        'snapshot_updated_at': updatedAt.toIso8601String(),
      };
}
