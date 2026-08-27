import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/time_format.dart';
import '../widgets/bookmark_row.dart';
import '../widgets/empty_state.dart';
import 'home_providers.dart';

/// ★タブ（§6.3）。`starred_at` 降順。初回起動時のデフォルトタブ。
class StarredTab extends ConsumerWidget {
  const StarredTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(starredListProvider);
    final snapshotUrls = ref.watch(snapshotUrlSetProvider);
    final titles = ref.watch(snapshotTitleByUrlProvider);

    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.star_border,
        message: 'まだお気に入りがありません',
      );
    }

    return ListView.builder(
      itemExtent: 48,
      itemCount: list.length,
      itemBuilder: (context, i) {
        final mark = list[i];
        return BookmarkRow(
          url: mark.url,
          title: titles[mark.url] ?? mark.title ?? '',
          inSnapshot: snapshotUrls.contains(mark.url),
          trailingMeta: mark.starredAt != null ? relativeJa(mark.starredAt!) : null,
        );
      },
    );
  }
}
