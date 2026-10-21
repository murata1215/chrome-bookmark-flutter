import 'package:flutter/material.dart';

/// パンくず。`crumbs` は根から現在地までのラベル列（根を含む）。
/// タップで `onTap(index)` が呼ばれる（0 = 根）。最後の要素はタップ不可（現在地）。
class BreadcrumbBar extends StatefulWidget {
  final List<String> crumbs;
  final ValueChanged<int> onTap;

  const BreadcrumbBar({super.key, required this.crumbs, required this.onTap});

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant BreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.crumbs.length != widget.crumbs.length) {
      // 階層が深くなっても現在地（右端）が常に見えるようにスクロール追従する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = widget.crumbs;
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: crumbs.length,
        separatorBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Center(
            child: Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ),
        ),
        itemBuilder: (context, i) {
          final isLast = i == crumbs.length - 1;
          return Center(
            child: TextButton(
              onPressed: isLast ? null : () => widget.onTap(i),
              style: TextButton.styleFrom(
                // disabled でも色を落とさない。現在地が一番「薄い」色の逆転を防ぐ
                // （TextButton の既定 disabled 色は onSurface の 38% で読みにくかった）。
                disabledForegroundColor: scheme.onSecondaryContainer,
                foregroundColor: scheme.primary,
                backgroundColor: isLast ? scheme.secondaryContainer : null,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: Text(
                crumbs[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: isLast ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          );
        },
      ),
    );
  }
}
