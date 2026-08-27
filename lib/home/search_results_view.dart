import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/bookmark_row.dart';
import '../widgets/empty_state.dart';
import 'home_providers.dart';

/// 検索結果のフラット一覧（§5・§9）。タブ横断で表示される。
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);

    if (results.isEmpty) {
      return const EmptyState(icon: Icons.search_off, message: '見つかりませんでした');
    }

    return ListView.builder(
      itemExtent: 48,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final item = results[i];
        return BookmarkRow(url: item.url, title: item.title, inSnapshot: item.inSnapshot);
      },
    );
  }
}
