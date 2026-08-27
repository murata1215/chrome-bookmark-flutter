import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/frecency.dart';
import '../core/models/folder_path.dart';
import '../core/models/mark.dart';
import '../core/providers.dart';
import '../core/search/search_index.dart';

/// 検索クエリ文字列。些末な UI 状態なので `StateProvider` のまま（§設計方針）。
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 検索結果の表示上限（§7・§9「表示上限200行」）。
const int kSearchResultLimit = 200;

// --- ライブラリタブ: 現在のフォルダ位置（§6.3「再起動時に前回位置へ復帰」） ---
// null = カテゴリ一覧（3ルート選択ページ）、非 null = ツリー表示中。

class CurrentFolderNotifier extends Notifier<FolderPath?> {
  @override
  FolderPath? build() => ref.read(prefsProvider).lastFolder;

  void _set(FolderPath? path) {
    state = path;
    // fire-and-forget: 表示の反応性を prefs 書き込み完了まで待たせない。
    final prefs = ref.read(prefsProvider);
    if (path == null) {
      prefs.clearLastFolder();
    } else {
      prefs.setLastFolder(path);
    }
  }

  /// カテゴリ一覧へ戻る。
  void goHome() => _set(null);

  void enter(FolderPathSegment segment) {
    final current = state;
    if (current == null) return;
    _set(current.appending(segment.title, segment.occurrence));
  }

  /// ルート直下で呼ぶとカテゴリ一覧へ戻る。
  void up() {
    final current = state;
    if (current == null) return;
    _set(current.segments.isEmpty ? null : current.parent);
  }

  void goToRoot(String rootKey) => _set(FolderPath(rootKey: rootKey, segments: const []));

  /// 同期でスナップショットが差し替わり浅くなった場合など、解決済みパスへ
  /// 明示的に同期させるために使う（tree_tab 側から呼ぶ）。
  void goTo(FolderPath path) => _set(path);
}

final currentFolderProvider =
    NotifierProvider<CurrentFolderNotifier, FolderPath?>(CurrentFolderNotifier.new);

/// スナップショット上に存在する URL の集合（`BookmarkRow` の「未登録」アイコン判定用）。
final snapshotUrlSetProvider = Provider<Set<String>>((ref) {
  final flat = ref.watch(snapshotProvider).flat;
  return {for (final fb in flat) fb.url};
});

/// 現在のフォルダ位置をスナップショットに対して解決した結果。
/// スナップショットが無い／カテゴリ一覧表示中は null。
final resolvedFolderProvider = Provider<ResolvedFolder?>((ref) {
  final snapshot = ref.watch(snapshotProvider).snapshot;
  final path = ref.watch(currentFolderProvider);
  if (snapshot == null || path == null) return null;
  return resolveFolderPath(snapshot, path);
});

// --- ★タブ: starred_at 降順（§6.3） ---

final starredListProvider = Provider<List<Mark>>((ref) {
  final marks = ref.watch(effectiveMarksProvider);
  final list = marks.values.where((m) => m.starred).toList();
  list.sort((a, b) {
    final aAt = a.starredAt;
    final bAt = b.starredAt;
    if (aAt != bAt) {
      if (aAt == null) return 1; // null は末尾
      if (bAt == null) return -1;
      final byAt = bAt.compareTo(aAt);
      if (byAt != 0) return byAt;
    }
    return a.url.compareTo(b.url);
  });
  return list;
});

// --- 頻度タブ: rankKey 降順・閾値以上のみ・上限50件（§3.1・§6.3） ---

final frequencyListProvider = Provider<List<Mark>>((ref) {
  final marks = ref.watch(effectiveMarksProvider);
  final now = ref.watch(prefsProvider).serverNow();

  final entries = <MapEntry<Mark, double>>[];
  for (final mark in marks.values) {
    // score <= 0（★のみでオープン実績が無い行）は log2(0) = -inf になるため除外。
    if (mark.score <= 0 || mark.scoreAt == null) continue;
    if (mark.effective(now) < kFrequencyThreshold) continue;
    entries.add(MapEntry(mark, rankKey(score: mark.score, scoreAt: mark.scoreAt!)));
  }

  entries.sort((a, b) {
    final byRank = b.value.compareTo(a.value);
    if (byRank != 0) return byRank;
    final aLast = a.key.lastOpenedAt;
    final bLast = b.key.lastOpenedAt;
    if (aLast != bLast) {
      if (aLast == null) return 1;
      if (bLast == null) return -1;
      final byLast = bLast.compareTo(aLast);
      if (byLast != 0) return byLast;
    }
    return a.key.url.compareTo(b.key.url);
  });

  return [for (final e in entries.take(kFrequencyLimit)) e.key];
});

// --- 検索: union(snapshot urls, marks urls) 上に AND 部分一致（§5・§9） ---

class SearchResultItem {
  final String url;
  final String title;
  final bool inSnapshot; // false ならスナップショットに存在しない URL（§5 の意図的仕様）

  const SearchResultItem({required this.url, required this.title, required this.inSnapshot});
}

final searchResultsProvider = Provider<List<SearchResultItem>>((ref) {
  final tokens = tokenize(ref.watch(searchQueryProvider));
  if (tokens.isEmpty) return const [];

  final flat = ref.watch(snapshotProvider).flat;
  final marks = ref.watch(effectiveMarksProvider);

  final results = <SearchResultItem>[];
  final addedUrls = <String>{};

  for (final fb in flat) {
    if (results.length >= kSearchResultLimit) break;
    if (addedUrls.contains(fb.url)) continue; // 重複URL（同一URLが2フォルダ）は1回だけ
    if (matchesAll(fb.haystack, tokens)) {
      addedUrls.add(fb.url);
      results.add(SearchResultItem(url: fb.url, title: fb.title, inSnapshot: true));
    }
  }

  if (results.length < kSearchResultLimit) {
    for (final mark in marks.values) {
      if (results.length >= kSearchResultLimit) break;
      if (addedUrls.contains(mark.url)) continue;
      final title = mark.title ?? '';
      final haystack = '$title\n${mark.url}'.toLowerCase();
      if (matchesAll(haystack, tokens)) {
        addedUrls.add(mark.url);
        results.add(SearchResultItem(url: mark.url, title: title, inSnapshot: false));
      }
    }
  }

  return results;
});
