import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/launcher/chrome_launcher.dart';
import '../core/models/pending.dart';
import '../core/providers.dart';
import '../core/url_utils.dart';
import 'favicon.dart';

const _uuid = Uuid();

/// 一覧共通の1行。★タブ・頻度タブ・ツリータブ・検索結果すべてがこれを使う。
/// Chrome のブックマークバーに合わせて1行構成（§W1）。ホスト名等の副情報は
/// タイトルの Tooltip（長押し/ホバー）と trailing 末尾の小さな文字に寄せる。
class BookmarkRow extends ConsumerWidget {
  final String url;
  final String title;
  final bool inSnapshot; // false: スナップショットに存在しない URL（§5・行は隠さない）
  final String? trailingMeta;

  const BookmarkRow({
    super.key,
    required this.url,
    required this.title,
    this.inSnapshot = true,
    this.trailingMeta,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = ref.watch(effectiveMarksProvider.select((m) => m[url]));
    final faviconEnabled = ref.watch(prefsProvider).faviconEnabled;
    final displayTitle = title.trim().isNotEmpty ? title : shortenUrl(url);
    final starred = mark?.starred ?? false;

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: FaviconAvatar(url: url, title: title, faviconEnabled: faviconEnabled),
      title: Tooltip(
        message: url,
        child: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!inSnapshot)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'ブックマークにありません',
                child: Icon(Icons.link_off, size: 14, color: Colors.grey),
              ),
            ),
          if (trailingMeta != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                trailingMeta!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          IconButton(
            icon: Icon(starred ? Icons.star : Icons.star_border),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            color: starred ? Colors.amber : null,
            tooltip: starred ? 'お気に入りから外す' : 'お気に入りに追加',
            onPressed: () => _toggleStar(ref, starred),
          ),
        ],
      ),
      onTap: () => _handleTap(context, ref),
    );
  }

  void _toggleStar(WidgetRef ref, bool currentlyStarred) {
    final now = ref.read(prefsProvider).serverNow();
    ref.read(pendingProvider.notifier).enqueueStar(
          PendingStar(url: url, starred: !currentlyStarred, changedAt: now),
        );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final kind = classifyScheme(url);
    if (kind == UrlKind.copyOnly) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コピーしました')),
        );
      }
      return;
    }

    // D-1（サーバー承認済みの仕様逸脱・§0-7）:
    // 1) opened_at はタップ時点で記録する（起動処理の所要時間を混ぜない）
    // 2) Chrome 優先起動を試みる（§6.5・chrome_launcher.dart）
    // 3) 起動が成功した時だけ frecency イベントを計上する
    final openedAt = ref.read(prefsProvider).serverNow();
    final launcher = ref.read(chromeLauncherProvider);
    final outcome = await launcher.open(url);

    if (outcome == LaunchOutcome.unsupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開けませんでした')),
        );
      }
      return;
    }

    ref.read(pendingProvider.notifier).enqueueOpen(
          PendingOpen(eventId: _uuid.v4(), url: url, openedAt: openedAt),
        );
  }
}
