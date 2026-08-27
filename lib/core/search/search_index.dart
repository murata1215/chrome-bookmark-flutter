/// 検索クエリをトークンに分割（空白区切り、小文字化）。
List<String> tokenize(String query) => query
    .trim()
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

/// haystack が全トークンを含む（AND・部分一致・大文字小文字無視）か。
bool matchesAll(String haystack, List<String> tokens) {
  if (tokens.isEmpty) return true;
  for (final t in tokens) {
    if (!haystack.contains(t)) return false;
  }
  return true;
}
