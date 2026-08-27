import 'package:flutter/material.dart';

/// パンくず。`crumbs` は根から現在地までのラベル列（根を含む）。
/// タップで `onTap(index)` が呼ばれる（0 = 根）。最後の要素はタップ不可（現在地）。
class BreadcrumbBar extends StatelessWidget {
  final List<String> crumbs;
  final ValueChanged<int> onTap;

  const BreadcrumbBar({super.key, required this.crumbs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: crumbs.length,
        separatorBuilder: (context, i) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Center(child: Icon(Icons.chevron_right, size: 16)),
        ),
        itemBuilder: (context, i) {
          final isLast = i == crumbs.length - 1;
          return Center(
            child: TextButton(
              onPressed: isLast ? null : () => onTap(i),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                crumbs[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isLast
                    ? Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold)
                    : Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        },
      ),
    );
  }
}
