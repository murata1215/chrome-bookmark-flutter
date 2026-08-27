import 'dart:math';

import '../frecency.dart';
import '../models/bookmark_node.dart';
import '../models/bookmark_snapshot.dart';
import '../models/mark.dart';

/// `MockApiClient` に与えるシードデータ。`small`/`medium`/`huge` の3種。
class MockSeed {
  final BookmarkSnapshot snapshot;
  final List<Mark> marks;

  const MockSeed({required this.snapshot, required this.marks});

  /// 約40URL・3ルート・4階層。ユニット/ウィジェットテストの正解データ。
  /// 境界ケース（同一URLが2フォルダ・同名兄弟フォルダ・タイトル空・
  /// javascript:・chrome://・長いタイトル・IDN風ホスト・クエリ+フラグメント・
  /// 空フォルダ・日本語のフォルダ名/タイトル）を全て含む。
  factory MockSeed.small() => _buildSmall();

  /// 約800URL。日常の開発用。
  factory MockSeed.medium() =>
      _buildSynthetic(urlCount: 800, seed: 42, treeHash: 'mock-medium-v1');

  /// 20,000URL（固定シードで実行時生成、§7 の性能検証用）。
  factory MockSeed.huge() =>
      _buildSynthetic(urlCount: 20000, seed: 7, treeHash: 'mock-huge-v1');
}

// --- 手動構築（境界ケースを網羅） ---

MockSeed _buildSmall() {
  final now = DateTime.now().toUtc();
  int addedMs(int daysAgo) => now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

  final longTitle = 'あ' * 120; // 120文字タイトル

  final bookmarkBar = BookmarkFolder(title: 'Bookmark Bar', dateAdded: addedMs(400), children: [
    BookmarkFolder(title: '仕事', dateAdded: addedMs(380), children: [
      BookmarkFolder(title: '2026', dateAdded: addedMs(370), children: [
        BookmarkUrl(
          title: 'GitHub - example/repo',
          dateAdded: addedMs(365),
          url: 'https://github.com/example/repo',
        ),
        BookmarkUrl(
          title: '査読ページ',
          dateAdded: addedMs(360),
          url: 'https://example.co.jp/review?ref=1&lang=ja#section-2',
        ),
      ]),
      // 同名の兄弟フォルダ2つ（「資料」が2つ、中身は別）。
      BookmarkFolder(title: '資料', dateAdded: addedMs(350), children: [
        BookmarkUrl(title: '資料A', dateAdded: addedMs(350), url: 'https://docs.example.com/a'),
      ]),
      BookmarkFolder(title: '資料', dateAdded: addedMs(340), children: [
        BookmarkUrl(title: '資料B', dateAdded: addedMs(340), url: 'https://docs.example.com/b'),
      ]),
    ]),
    BookmarkFolder(title: '個人', dateAdded: addedMs(300), children: [
      BookmarkUrl(title: '', dateAdded: addedMs(295), url: 'https://xn--wgv71a119e.example/'), // タイトル空 + IDN風ホスト
      const BookmarkUrl(title: 'ブックマークレット', dateAdded: 0, url: 'javascript:alert(1)'),
      const BookmarkUrl(title: 'Chrome設定', dateAdded: 0, url: 'chrome://bookmarks'),
      BookmarkUrl(title: longTitle, dateAdded: addedMs(290), url: 'https://example.com/long-title'),
    ]),
    const BookmarkFolder(title: '空フォルダ', dateAdded: 0, children: []),
  ]);

  final other = BookmarkFolder(title: 'Other Bookmarks', dateAdded: addedMs(400), children: [
    // 同一URLが2フォルダに存在するケース（bookmark_bar の GitHub と同じ URL）。
    BookmarkUrl(
      title: 'GitHub - example/repo (other)',
      dateAdded: addedMs(200),
      url: 'https://github.com/example/repo',
    ),
    BookmarkFolder(title: 'ニュース', dateAdded: addedMs(200), children: [
      const BookmarkUrl(title: 'Example News', dateAdded: 0, url: 'https://news.example.com/top'),
      const BookmarkUrl(title: 'Tech Blog', dateAdded: 0, url: 'https://blog.example.dev/post/1'),
    ]),
  ]);

  final mobile = BookmarkFolder(title: 'Mobile Bookmarks', dateAdded: addedMs(100), children: [
    BookmarkFolder(title: 'モバイル保存', dateAdded: addedMs(90), children: [
      const BookmarkUrl(title: 'Recipe', dateAdded: 0, url: 'https://cooking.example.com/recipe/42'),
      const BookmarkUrl(title: 'Map', dateAdded: 0, url: 'https://maps.example.com/place/tokyo'),
    ]),
  ]);

  final snapshot = BookmarkSnapshot(
    treeHash: 'mock-small-v1',
    roots: {'bookmark_bar': bookmarkBar, 'other': other, 'mobile': mobile},
    updatedAt: now,
  );

  final treeUrls = <String>[
    'https://github.com/example/repo',
    'https://example.co.jp/review?ref=1&lang=ja#section-2',
    'https://docs.example.com/a',
    'https://docs.example.com/b',
    'https://example.com/long-title',
    'https://news.example.com/top',
    'https://blog.example.dev/post/1',
    'https://cooking.example.com/recipe/42',
    'https://maps.example.com/place/tokyo',
  ];

  final random = Random(1);
  final marks = <Mark>[];

  void addMark(
    String url, {
    required int daysAgoOpened,
    required int openCount,
    bool starred = false,
    String? title,
  }) {
    final scoreAt = now.subtract(Duration(days: daysAgoOpened));
    double score = 0;
    for (var i = 0; i < openCount; i++) {
      score = applyOpen(score: score, scoreAt: i == 0 ? null : scoreAt, openedAt: scoreAt).score;
    }
    marks.add(Mark(
      url: url,
      starred: starred,
      starredAt: starred ? scoreAt : null,
      openCount: openCount,
      score: score,
      scoreAt: openCount > 0 ? scoreAt : null,
      lastOpenedAt: openCount > 0 ? scoreAt : null,
      updatedAt: scoreAt,
      title: title,
    ));
  }

  for (final url in treeUrls) {
    addMark(
      url,
      daysAgoOpened: random.nextInt(90) + 1,
      openCount: random.nextInt(10) + 1,
      starred: random.nextBool(),
    );
  }

  // 0.1 の閾値のすぐ上・下（単発オープンで decay(Δ) が 0.1 を挟む）。
  addMark('https://threshold.example.com/above', daysAgoOpened: 29, openCount: 1); // decay(29d)≈0.51 > 0.1
  addMark('https://threshold.example.com/below', daysAgoOpened: 110, openCount: 1); // decay(110d)≈0.086 < 0.1

  // ★のみ（score=0, score_at=null）のマーク。
  marks.add(Mark(
    url: 'https://starred-only.example.com/',
    starred: true,
    starredAt: now.subtract(const Duration(days: 5)),
    openCount: 0,
    score: 0,
    scoreAt: null,
    lastOpenedAt: null,
    updatedAt: now.subtract(const Duration(days: 5)),
  ));

  // スナップショットに存在しない URL のマーク（15件）。
  for (var i = 0; i < 15; i++) {
    addMark(
      'https://removed-$i.example.com/page',
      daysAgoOpened: random.nextInt(60) + 1,
      openCount: random.nextInt(5) + 1,
      title: '削除済みブックマーク$i',
    );
  }

  return MockSeed(snapshot: snapshot, marks: marks);
}

// --- 合成生成（medium/huge。固定シードで実行時生成、5MB のアセットはコミットしない） ---

MockSeed _buildSynthetic({required int urlCount, required int seed, required String treeHash}) {
  final random = Random(seed);
  final now = DateTime.now().toUtc();
  final nowMs = now.millisecondsSinceEpoch;

  final domains = List.generate(30, (i) => 'site$i.example.com');
  final folderNames = ['仕事', 'プライベート', '開発', '読み物', 'ツール', 'ニュース', 'ショッピング', 'エンタメ'];

  var urlIndex = 0;
  BookmarkFolder buildFolder(String title, int depth) {
    final childrenCount = depth <= 0 ? 0 : (3 + random.nextInt(4));
    final children = <BookmarkNode>[];
    for (var i = 0; i < childrenCount && urlIndex < urlCount; i++) {
      if (depth > 1 && random.nextDouble() < 0.3) {
        children.add(buildFolder(folderNames[random.nextInt(folderNames.length)], depth - 1));
      } else {
        final domain = domains[random.nextInt(domains.length)];
        children.add(BookmarkUrl(
          title: 'Item $urlIndex',
          dateAdded: nowMs,
          url: 'https://$domain/item/$urlIndex',
        ));
        urlIndex++;
      }
    }
    return BookmarkFolder(title: title, dateAdded: nowMs, children: children);
  }

  final roots = <String, BookmarkFolder>{};
  for (var rootIdx = 0; rootIdx < kRootKeys.length; rootIdx++) {
    final key = kRootKeys[rootIdx];
    final targetForRoot = (urlCount * (rootIdx + 1)) ~/ kRootKeys.length;
    final rootChildren = <BookmarkNode>[];
    while (urlIndex < targetForRoot) {
      rootChildren.add(buildFolder(folderNames[random.nextInt(folderNames.length)], 4));
    }
    roots[key] = BookmarkFolder(title: rootLabel(key), dateAdded: nowMs, children: rootChildren);
  }

  final snapshot = BookmarkSnapshot(treeHash: treeHash, roots: roots, updatedAt: now);

  // marks: URL の約60%に付与。
  final marks = <Mark>[];
  void walk(BookmarkNode node) {
    if (node is BookmarkFolder) {
      for (final c in node.children) {
        walk(c);
      }
    } else if (node is BookmarkUrl) {
      if (random.nextDouble() < 0.6) {
        final daysAgo = random.nextInt(90) + 1;
        final scoreAt = now.subtract(Duration(days: daysAgo));
        final openCount = random.nextInt(20) + 1;
        final isStarred = random.nextDouble() < 0.1;
        double score = 0;
        for (var i = 0; i < openCount; i++) {
          score = applyOpen(score: score, scoreAt: i == 0 ? null : scoreAt, openedAt: scoreAt).score;
        }
        marks.add(Mark(
          url: node.url,
          starred: isStarred,
          starredAt: isStarred ? scoreAt : null,
          openCount: openCount,
          score: score,
          scoreAt: scoreAt,
          lastOpenedAt: scoreAt,
          updatedAt: scoreAt,
        ));
      }
    }
  }

  for (final r in roots.values) {
    walk(r);
  }

  return MockSeed(snapshot: snapshot, marks: marks);
}
