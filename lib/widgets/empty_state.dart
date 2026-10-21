import 'package:flutter/material.dart';

/// 空状態（★後方互換: `icon`/`message` だけの既存呼び出しも無変更で動く）。
/// `headline` + CTA を足せるようにし、素のアイコンの代わりにトーナルな円で
/// 面積と色を与える。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? headline;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// ツリーの「空のフォルダです」等、控えめに出したい場合は true。
  final bool compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.headline,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 76,
              height: compact ? 56 : 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: s.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 26 : 34, color: s.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (headline != null) ...[
              Text(headline!, textAlign: TextAlign.center, style: textTheme.titleMedium),
              const SizedBox(height: 6),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
