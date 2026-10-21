import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// 初回ロード中のスケルトン行リスト。`shimmer` パッケージを足すほどの規模ではない
/// （40 行程度で足りる）ため自前実装にしている。「視差効果を減らす」設定時は
/// シマーを止めて静止表示に落とす（[AppMotion.of] と同じ a11y 方針）。
class SkeletonList extends StatefulWidget {
  final int rows;

  const SkeletonList({super.key, this.rows = 8});

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final rows = Column(
      children: [
        for (var i = 0; i < widget.rows; i++)
          SizedBox(
            height: AppSpacing.rowMinHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.rowH, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: sem.skeletonBase,
                      borderRadius: BorderRadius.circular(AppRadius.avatar),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3 + (i * 7) % 5, // 行ごとに長さを散らして「リストらしく」見せる
                    child: Container(
                      height: 11,
                      decoration: BoxDecoration(
                        color: sem.skeletonBase,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Expanded(flex: 2 + (i * 3) % 4, child: const SizedBox()),
                ],
              ),
            ),
          ),
      ],
    );

    final content = ExcludeSemantics(child: rows);
    if (reduceMotion) return content;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.0 - 2 * (1 - _controller.value), 0),
            end: Alignment(1.0 - 2 * (1 - _controller.value), 0),
            colors: [sem.skeletonBase, sem.skeletonHighlight, sem.skeletonBase],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(rect),
          child: child,
        );
      },
      child: content,
    );
  }
}
