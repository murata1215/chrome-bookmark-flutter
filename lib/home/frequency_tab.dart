import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/time_format.dart';
import '../widgets/bookmark_row.dart';
import '../widgets/empty_state.dart';
import 'home_providers.dart';

/// 頻度タブ（§3.1・§6.3）。`rankKey` 降順・`effective >= 0.1` のみ・上限50件。
class FrequencyTab extends ConsumerWidget {
  const FrequencyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(frequencyListProvider);
    final snapshotUrls = ref.watch(snapshotUrlSetProvider);
    final titles = ref.watch(snapshotTitleByUrlProvider);

    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.trending_up_outlined,
        message: 'よく開くブックマークがここに表示されます',
      );
    }

    return ListView.builder(
      itemExtent: 48,
      itemCount: list.length,
      itemBuilder: (context, i) {
        final mark = list[i];
        final lastOpened = mark.lastOpenedAt;
        return BookmarkRow(
          url: mark.url,
          title: titles[mark.url] ?? mark.title ?? '',
          inSnapshot: snapshotUrls.contains(mark.url),
          trailingMeta:
              '${mark.openCount}回${lastOpened != null ? ' / ${relativeJa(lastOpened)}' : ''}',
        );
      },
    );
  }
}
