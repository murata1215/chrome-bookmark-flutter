import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/bookmark_snapshot.dart';
import '../core/providers.dart';
import '../core/sync/sync_service.dart';
import '../core/time_format.dart';
import '../settings/settings_screen.dart';
import 'home_providers.dart';
import 'tree_tab.dart';

/// 左端タブ「ライブラリ」。カテゴリ一覧（3ルート選択）⇄ ツリーを
/// `currentFolderProvider`（`FolderPath?`）で切り替える。null ならカテゴリ一覧。
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(currentFolderProvider);
    return path == null ? const _CategoryPage() : const TreeTab();
  }
}

const Map<String, IconData> _rootIcons = {
  'bookmark_bar': Icons.bookmarks_outlined,
  'other': Icons.folder_special_outlined,
  'mobile': Icons.smartphone_outlined,
};

class _CategoryPage extends ConsumerWidget {
  const _CategoryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider).snapshot;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => ref.read(syncServiceProvider).syncNow(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final key in kRootKeys) ...[
            _RootCard(
              rootKey: key,
              count: snapshot?.roots[key]?.children.length,
              color: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SyncFooter(),
        ],
      ),
    );
  }
}

class _RootCard extends ConsumerWidget {
  final String rootKey;
  final int? count;
  final Color color;

  const _RootCard({required this.rootKey, required this.count, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            _rootIcons[rootKey] ?? Icons.folder_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(rootLabel(rootKey), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: count == null ? null : Text('$count 件'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => ref.read(currentFolderProvider.notifier).goToRoot(rootKey),
      ),
    );
  }
}

class _SyncFooter extends ConsumerWidget {
  const _SyncFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final status = ref.watch(syncStatusProvider);
    final lastSyncAt = prefs.lastSyncAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              lastSyncAt == null ? '未同期' : '最終同期: ${relativeJa(lastSyncAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          if (status.isSyncing)
            const SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '今すぐ同期',
              onPressed: () => ref.read(syncServiceProvider).syncNow(force: true),
            ),
        ],
      ),
    );
  }
}
