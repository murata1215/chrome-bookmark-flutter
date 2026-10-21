import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// ツリータブのフォルダ行。leading は [FaviconAvatar] と同じ 24px・同じ角丸の
/// タイルにして、「フォルダ＝単色タイル／ブックマーク＝カラフルなファビコン」
/// という種別差を同じ形状言語の中で表現する。
class FolderRow extends StatelessWidget {
  final String title;
  final int itemCount; // 負数なら非表示
  final VoidCallback onTap;

  const FolderRow({
    super.key,
    required this.title,
    this.itemCount = -1,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: AppSpacing.rowH, right: 4),
      leading: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.avatar),
        ),
        child: Icon(Icons.folder_rounded, size: 15, color: s.onSecondaryContainer),
      ),
      title: Text(
        title.isEmpty ? '(無題のフォルダ)' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (itemCount >= 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '$itemCount 件',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant),
              ),
            ),
          Icon(Icons.chevron_right, color: s.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}
