import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/sync/sync_service.dart';
import '../core/time_format.dart';
import '../widgets/bookmark_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/frequency_meter.dart';
import 'home_providers.dart';

/// 頻度タブ（§3.1・§6.3）。`rankKey` 降順・`effective >= 0.1` のみ・上限50件。
class FrequencyTab extends ConsumerWidget {
  const FrequencyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(frequencyListProvider);
    final snapshotUrls = ref.watch(snapshotUrlSetProvider);
    final titles = ref.watch(snapshotTitleByUrlProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(syncServiceProvider).syncNow(force: true),
      child: list.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: EmptyState(
                    icon: Icons.trending_up_outlined,
                    headline: 'よく開くページがここに並びます',
                    message: '何度か開くと、使用頻度の高い順に自動で並びます',
                    actionLabel: 'ブックマークを見る',
                    onAction: () => ref.read(homeTabIndexProvider.notifier).select(0),
                  ),
                ),
              ),
            )
          : Builder(
              builder: (context) {
                // frecency.dart のコメントどおり rankKey 降順は effective 降順と
                // 完全に一致するため、list.first が常に最大値（追加の走査は不要）。
                final now = ref.watch(prefsProvider).serverNow();
                final maxEff = list.first.effective(now);
                return ListView.builder(
                  key: const PageStorageKey('frequency'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  prototypeItem: const BookmarkRow(url: 'https://example.com', title: 'プロトタイプ'),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final mark = list[i];
                    final lastOpened = mark.lastOpenedAt;
                    final eff = mark.effective(now);
                    // 線形だと指数減衰で2位以降が潰れるため平方根で圧縮する。
                    final ratio = maxEff <= 0 ? 0.0 : math.sqrt((eff / maxEff).clamp(0.0, 1.0));
                    return BookmarkRow(
                      url: mark.url,
                      title: titles[mark.url] ?? mark.title ?? '',
                      inSnapshot: snapshotUrls.contains(mark.url),
                      trailingWidget: FrequencyMeter(
                        ratio: ratio,
                        openCount: mark.openCount,
                        isTop: i < 3,
                      ),
                      semanticMeta: '${mark.openCount}回'
                          '${lastOpened != null ? '、最終 ${relativeJa(lastOpened)}' : ''}',
                    );
                  },
                );
              },
            ),
    );
  }
}
