import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/design_tokens.dart';
import '../core/launcher/chrome_launcher.dart';
import '../core/models/pending.dart';
import '../core/providers.dart';
import '../core/url_utils.dart';
import 'app_snack.dart';
import 'favicon.dart';

const _uuid = Uuid();

/// 一覧共通の1行。★タブ・頻度タブ・ツリータブ・検索結果すべてがこれを使う。
/// Chrome のブックマークバーに合わせて1行構成（§W1）。ホスト名等の副情報は
/// タイトルの Tooltip（長押し/ホバー）と trailing 末尾の小さな文字に寄せる。
///
/// 1 行の高さは常に一定（★/頻度/ツリーは [secondary] を渡さない）。検索結果
/// だけホスト名＋フォルダパスが効くため [secondary] で 2 行化する（§3-2）。
class BookmarkRow extends ConsumerWidget {
  final String url;
  final String title;
  final bool inSnapshot; // false: スナップショットに存在しない URL（§5・行は隠さない）
  final String? trailingMeta;

  /// 検索結果専用: ホスト名＋フォルダパス等の 2 行目。渡した時だけ行が高くなる。
  final String? secondary;

  /// `trailingMeta` の代わりにカスタム Widget を出す（頻度バー等）。
  final Widget? trailingWidget;

  /// `trailingWidget` 使用時、スクリーンリーダー向けに読み上げる文章
  /// （視覚エンコーディングはそのままでは意味を持たないため）。
  final String? semanticMeta;

  const BookmarkRow({
    super.key,
    required this.url,
    required this.title,
    this.inSnapshot = true,
    this.trailingMeta,
    this.secondary,
    this.trailingWidget,
    this.semanticMeta,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = ref.watch(effectiveMarksProvider.select((m) => m[url]));
    final faviconEnabled = ref.watch(prefsProvider).faviconEnabled;
    final displayTitle = title.trim().isNotEmpty ? title : shortenUrl(url);
    final starred = mark?.starred ?? false;
    final sem = context.sem;

    final metaText = trailingWidget == null && trailingMeta != null
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              trailingMeta!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : null;

    final semanticLabel = StringBuffer(displayTitle);
    if (semanticMeta != null) semanticLabel.write('、$semanticMeta');
    if (starred) semanticLabel.write('、お気に入り');
    if (!inSnapshot) semanticLabel.write('、ブックマークにありません');

    return Semantics(
      button: true,
      label: semanticLabel.toString(),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: AppSpacing.rowH, right: 4),
        leading: FaviconAvatar(url: url, title: title, faviconEnabled: faviconEnabled),
        title: ExcludeSemantics(
          child: Tooltip(
            message: url,
            child: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        subtitle: secondary == null
            ? null
            : ExcludeSemantics(
                child: Text(secondary!, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
        trailing: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!inSnapshot)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'ブックマークにありません',
                    child: Icon(Icons.link_off, size: 14, color: sem.offline),
                  ),
                ),
              ?metaText,
              if (trailingWidget != null)
                Padding(padding: const EdgeInsets.only(right: 4), child: trailingWidget),
              _StarButton(starred: starred, onPressed: () => _toggleStar(ref, starred)),
            ],
          ),
        ),
        onTap: () => _handleTap(context, ref),
        onLongPress: () => _showActions(context, ref, starred),
      ),
    );
  }

  void _toggleStar(WidgetRef ref, bool currentlyStarred) {
    final now = ref.read(prefsProvider).serverNow();
    ref
        .read(pendingProvider.notifier)
        .enqueueStar(PendingStar(url: url, starred: !currentlyStarred, changedAt: now));
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final kind = classifyScheme(url);
    if (kind == UrlKind.copyOnly) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        showAppSnack(context, 'コピーしました', icon: Icons.copy_rounded);
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
        showAppSnack(
          context,
          '開けませんでした',
          icon: Icons.error_outline,
          isError: true,
          action: SnackBarAction(
            label: 'コピー',
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        );
      }
      return;
    }

    ref
        .read(pendingProvider.notifier)
        .enqueueOpen(PendingOpen(eventId: _uuid.v4(), url: url, openedAt: openedAt));
  }

  void _showActions(BuildContext context, WidgetRef ref, bool starred) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(color: sheetContext.scheme.onSurfaceVariant),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('開く'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleTap(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('URL をコピー'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    showAppSnack(context, 'コピーしました', icon: Icons.copy_rounded);
                  }
                },
              ),
              ListTile(
                leading: Icon(starred ? Icons.star_outline_rounded : Icons.star_rounded),
                title: Text(starred ? 'お気に入りから外す' : 'お気に入りに追加'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleStar(ref, starred);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StarButton extends StatelessWidget {
  final bool starred;
  final VoidCallback onPressed;

  const _StarButton({required this.starred, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return IconButton(
      iconSize: 20,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.tapTarget,
        height: AppSpacing.tapTarget,
      ),
      padding: EdgeInsets.zero,
      tooltip: starred ? 'お気に入りから外す' : 'お気に入りに追加',
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      icon: TweenAnimationBuilder<double>(
        key: ValueKey(starred),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, AppMotion.emphasized),
        curve: Curves.easeOut,
        builder: (context, t, child) {
          return Transform.scale(scale: 1 + 0.30 * math.sin(math.pi * t), child: child);
        },
        child: Icon(
          starred ? Icons.star_rounded : Icons.star_outline_rounded,
          color: starred ? sem.star : sem.starIdle,
        ),
      ),
    );
  }
}
