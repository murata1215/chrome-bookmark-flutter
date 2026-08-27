import 'package:chrome_bookmark_flutter/core/models/bookmark_node.dart';
import 'package:chrome_bookmark_flutter/core/models/bookmark_snapshot.dart';
import 'package:chrome_bookmark_flutter/core/models/folder_path.dart';
import 'package:flutter_test/flutter_test.dart';

BookmarkSnapshot _snapshotFrom(BookmarkFolder bar) => BookmarkSnapshot(
      treeHash: 't',
      roots: {'bookmark_bar': bar},
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('resolveFolderPath', () {
    test('タイトル+出現順が一致すればそのまま解決できる（同名兄弟）', () {
      final bar = const BookmarkFolder(title: 'Bar', dateAdded: 0, children: [
        BookmarkFolder(title: '資料', dateAdded: 0, children: [
          BookmarkUrl(title: 'A', dateAdded: 0, url: 'https://a.example/'),
        ]),
        BookmarkFolder(title: '資料', dateAdded: 0, children: [
          BookmarkUrl(title: 'B', dateAdded: 0, url: 'https://b.example/'),
        ]),
      ]);
      final snapshot = _snapshotFrom(bar);

      final path0 = const FolderPath(rootKey: 'bookmark_bar', segments: [
        FolderPathSegment(title: '資料', occurrence: 0),
      ]);
      final resolved0 = resolveFolderPath(snapshot, path0);
      expect(resolved0.exact, isTrue);
      expect((resolved0.folder.children.single as BookmarkUrl).url, 'https://a.example/');

      final path1 = const FolderPath(rootKey: 'bookmark_bar', segments: [
        FolderPathSegment(title: '資料', occurrence: 1),
      ]);
      final resolved1 = resolveFolderPath(snapshot, path1);
      expect(resolved1.exact, isTrue);
      expect((resolved1.folder.children.single as BookmarkUrl).url, 'https://b.example/');
    });

    test('リネームされていれば一致しなくなり、その手前で止まる（根まで戻らない）', () {
      final bar = const BookmarkFolder(title: 'Bar', dateAdded: 0, children: [
        BookmarkFolder(title: '仕事', dateAdded: 0, children: [
          BookmarkFolder(title: '2027（旧: 2026）', dateAdded: 0, children: []),
        ]),
      ]);
      final snapshot = _snapshotFrom(bar);

      final saved = const FolderPath(rootKey: 'bookmark_bar', segments: [
        FolderPathSegment(title: '仕事', occurrence: 0),
        FolderPathSegment(title: '2026', occurrence: 0), // リネームされて消えた
      ]);
      final resolved = resolveFolderPath(snapshot, saved);
      expect(resolved.exact, isFalse);
      expect(resolved.folder.title, '仕事'); // 辿れた最深フォルダで停止
      expect(resolved.path.segments, hasLength(1));
    });

    test('削除されたフォルダでも根まで戻らず親で停止する', () {
      final bar = const BookmarkFolder(title: 'Bar', dateAdded: 0, children: [
        BookmarkFolder(title: '仕事', dateAdded: 0, children: []),
      ]);
      final snapshot = _snapshotFrom(bar);

      final saved = const FolderPath(rootKey: 'bookmark_bar', segments: [
        FolderPathSegment(title: '仕事', occurrence: 0),
        FolderPathSegment(title: '2026', occurrence: 0),
        FolderPathSegment(title: '深い', occurrence: 0),
      ]);
      final resolved = resolveFolderPath(snapshot, saved);
      expect(resolved.exact, isFalse);
      expect(resolved.folder.title, '仕事');
    });

    test('出現順だけがずれた場合（並べ替え）は先頭一致にフォールバック', () {
      final bar = const BookmarkFolder(title: 'Bar', dateAdded: 0, children: [
        BookmarkFolder(title: '資料', dateAdded: 0, children: [
          BookmarkUrl(title: 'A', dateAdded: 0, url: 'https://a.example/'),
        ]),
      ]);
      final snapshot = _snapshotFrom(bar);

      // occurrence:1 だが実際は0個目しか無い → フォールバックで最初の1つを使う。
      final saved = const FolderPath(rootKey: 'bookmark_bar', segments: [
        FolderPathSegment(title: '資料', occurrence: 1),
      ]);
      final resolved = resolveFolderPath(snapshot, saved);
      expect(resolved.folder.title, '資料');
      expect(resolved.exact, isFalse); // occurrence がずれているので exact ではない
    });
  });

  group('segmentForChild', () {
    test('同名兄弟の中での出現順を正しく数える', () {
      final parent = const BookmarkFolder(title: 'Bar', dateAdded: 0, children: [
        BookmarkFolder(title: '資料', dateAdded: 0, children: []),
        BookmarkFolder(title: '他', dateAdded: 0, children: []),
        BookmarkFolder(title: '資料', dateAdded: 0, children: []),
      ]);
      expect(segmentForChild(parent, 0).occurrence, 0);
      expect(segmentForChild(parent, 2).occurrence, 1);
    });
  });

  group('FolderPath', () {
    test('toJson/fromJson の往復', () {
      final path = FolderPath.root.appending('仕事', 0).appending('2026', 1);
      final restored = FolderPath.fromJson(path.toJson());
      expect(restored.rootKey, path.rootKey);
      expect(restored.segments.map((s) => (s.title, s.occurrence)),
          path.segments.map((s) => (s.title, s.occurrence)));
    });

    test('parent は末尾セグメントを1つ取り除く', () {
      final path = FolderPath.root.appending('仕事', 0).appending('2026', 0);
      expect(path.parent.segments, hasLength(1));
      expect(path.parent.parent.segments, isEmpty);
      expect(path.parent.parent.parent.segments, isEmpty); // ルートでは変化しない
    });
  });
}
