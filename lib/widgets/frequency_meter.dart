import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// 頻度タブの「12回」を比較しやすくするための細いバー。
///
/// エンコーディングは「長さ」1 本だけ、色は「上位3件かどうか」の 1 ビットのみ。
/// 軸・目盛り・凡例は付けない（やりすぎを避ける）。回数テキストは正確さの
/// 担保として残す。
class FrequencyMeter extends StatelessWidget {
  final double ratio; // 0..1（最大値に対する比。呼び出し側で sqrt 圧縮済み）
  final int openCount;
  final bool isTop;

  const FrequencyMeter({
    super.key,
    required this.ratio,
    required this.openCount,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 4,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: sem.meterTrack, borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio.clamp(0.08, 1.0), // 最小 8% で「存在」は見せる
            child: Container(
              decoration: BoxDecoration(
                color: isTop ? sem.meterFillTop : sem.meterFill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$openCount',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isTop ? context.scheme.onSurface : context.scheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
