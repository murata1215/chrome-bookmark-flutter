/// 「3日前」「たった今」等の簡易日本語相対時刻フォーマット（intl 非依存）。
String relativeJa(DateTime time, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toUtc();
  final t = time.toUtc();
  final diff = n.difference(t);

  if (diff.isNegative) return 'たった今';
  if (diff.inSeconds < 60) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  if (diff.inDays < 30) return '${diff.inDays}日前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}ヶ月前';
  return '${(diff.inDays / 365).floor()}年前';
}
