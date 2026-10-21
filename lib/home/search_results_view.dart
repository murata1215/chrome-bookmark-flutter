import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/url_utils.dart';
import '../widgets/bookmark_row.dart';
import '../widgets/empty_state.dart';
import 'home_providers.dart';

/// 検索結果のフラット一覧（§5・§9）。タブ横断で表示される。
/// ★/頻度/ツリーと違い「思い出せないものを探す」用途なのでホスト名を
/// 2 行目に出す（§3-2）。ローカル計算のため RefreshIndicator は付けない。
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider).trim();

    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        headline: query.isEmpty ? '見つかりませんでした' : '「$query」に一致なし',
        message: 'スペース区切りは AND 検索です。語を減らすと見つかるかもしれません',
      );
    }

    return ListView.builder(
      key: const PageStorageKey('search'),
      prototypeItem: BookmarkRow(url: 'https://example.com', title: 'プロトタイプ', secondary: 'example.com'),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final item = results[i];
        return BookmarkRow(
          url: item.url,
          title: item.title,
          inSnapshot: item.inSnapshot,
          secondary: displaySubtitle(item.url),
        );
      },
    );
  }
}
