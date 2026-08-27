import 'package:flutter/material.dart';

/// ツリータブのフォルダ行。
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
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: const Icon(Icons.folder),
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
