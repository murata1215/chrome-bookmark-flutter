import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/bookmark_node.dart';
import '../core/models/bookmark_snapshot.dart';
import '../core/models/folder_path.dart';
import '../widgets/bookmark_row.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/folder_row.dart';
import 'home_providers.dart';

/// ツリータブ（§6.3）。ライブラリのカテゴリページからルートを選んだ後の
/// 潜る → パンくず表示。フォルダ同定は `FolderPath`（タイトル＋兄弟内出現順）で行う
/// （§4.3 に id が無いため）。
class TreeTab extends ConsumerWidget {
  const TreeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(resolvedFolderProvider);
    final currentPath = ref.watch(currentFolderProvider);

    if (currentPath == null) {
      // カテゴリ一覧へ遷移中の一瞬など。LibraryTab 側で分岐しているので通常は来ない。
      return const SizedBox.shrink();
    }

    if (resolved == null) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        message: '読み込み中、またはブックマークがまだありません',
      );
    }

    // 解決結果が保存パスより浅い（フォルダが削除・リネームされた等）場合は、
    // 実際に辿れた場所へ保存位置を同期し、SnackBar で知らせる（§4.3「根まで戻さない」）。
    if (!resolved.exact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(currentFolderProvider.notifier).goTo(resolved.path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('フォルダの構成が変わったため、上の階層に戻りました')),
        );
      });
    }

    final children = resolved.folder.children;
    final crumbs = [
      rootLabel(currentPath.rootKey),
      ...resolved.path.segments.map((s) => s.title.isEmpty ? '(無題のフォルダ)' : s.title),
    ];

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'ライブラリ',
              onPressed: () => ref.read(currentFolderProvider.notifier).goHome(),
            ),
            Expanded(
              child: BreadcrumbBar(
                crumbs: crumbs,
                onTap: (i) {
                  final notifier = ref.read(currentFolderProvider.notifier);
                  if (i == 0) {
                    notifier.goToRoot(currentPath.rootKey);
                  } else {
                    final segs = resolved.path.segments.sublist(0, i - 1);
                    notifier.goTo(FolderPath(rootKey: currentPath.rootKey, segments: segs));
                  }
                },
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: children.isEmpty
              ? const EmptyState(icon: Icons.folder_open, message: '空のフォルダです')
              : ListView.builder(
                  itemExtent: 48,
                  itemCount: children.length,
                  itemBuilder: (context, i) {
                    final node = children[i];
                    if (node is BookmarkFolder) {
                      return FolderRow(
                        title: node.title,
                        itemCount: node.children.length,
                        onTap: () => ref
                            .read(currentFolderProvider.notifier)
                            .enter(segmentForChild(resolved.folder, i)),
                      );
                    }
                    final url = node as BookmarkUrl;
                    return BookmarkRow(url: url.url, title: url.title);
                  },
                ),
        ),
      ],
    );
  }
}
