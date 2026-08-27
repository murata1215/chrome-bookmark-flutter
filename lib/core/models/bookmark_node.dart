/// §4.3 正規化ノード。id / parentId / index は持たない。
sealed class BookmarkNode {
  final String title;
  final int dateAdded; // epoch ms

  const BookmarkNode({required this.title, required this.dateAdded});

  factory BookmarkNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'folder') {
      final childrenJson = (json['children'] as List<dynamic>? ?? const []);
      return BookmarkFolder(
        title: (json['title'] as String?) ?? '',
        dateAdded: _asInt(json['date_added']),
        children: childrenJson
            .whereType<Map<String, dynamic>>()
            .map(BookmarkNode.fromJson)
            .toList(growable: false),
      );
    }
    // type == 'url' または不明な type は url ノードとして扱う（url が無ければ弾く）
    return BookmarkUrl(
      title: (json['title'] as String?) ?? '',
      dateAdded: _asInt(json['date_added']),
      url: (json['url'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson();

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class BookmarkFolder extends BookmarkNode {
  final List<BookmarkNode> children;

  const BookmarkFolder({
    required super.title,
    required super.dateAdded,
    required this.children,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'folder',
        'title': title,
        'date_added': dateAdded,
        'children': children.map((c) => c.toJson()).toList(),
      };
}

class BookmarkUrl extends BookmarkNode {
  final String url;

  const BookmarkUrl({
    required super.title,
    required super.dateAdded,
    required this.url,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'url',
        'title': title,
        'date_added': dateAdded,
        'url': url,
      };
}
