/// QR の生値（[rawValue]）からペアリングコードを抽出する純関数（§6.3・§0-4想定）。
///
/// 3分岐:
/// ① `https://chrome-bookmark.devrelay.io/...?code=12345678` のような URL →
///    ホストが信頼ホストと一致し、`code` クエリパラメータが8桁数字の場合のみ採用。
///    **QR からベース URL は絶対に採用しない**（悪意ある QR で別サーバーへ誘導される
///    のを防ぐため、常に `AppConfig.apiBaseUrl` を使う。ここではホストの一致確認にのみ使う）。
/// ② 生の8桁数字文字列。
/// ③ どちらでもなければ null（読み取りを継続する。フレーム毎にエラートーストは出さない）。
///
/// 信頼ホスト以外（悪意あるホストを含む）の URL は、たとえ `code` クエリを含んでいても
/// **拒否する**（他分岐へのフォールバックはしない）。
const trustedPairingHost = 'chrome-bookmark.devrelay.io';

final _eightDigitCode = RegExp(r'^\d{8}$');

String? extractPairingCode(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.host.isNotEmpty) {
    // ①信頼ホストの URL。code クエリが有効な時だけ採用し、それ以外は
    //   （他のホストの可能性も含めて）ここで確定的に拒否する。
    if (uri.host == trustedPairingHost) {
      final code = uri.queryParameters['code'];
      return (code != null && _eightDigitCode.hasMatch(code)) ? code : null;
    }
    // 信頼ホスト以外の URL は拒否（生の8桁数字ではないため②にも該当しない）。
    return null;
  }

  // ②生の8桁数字。
  if (_eightDigitCode.hasMatch(trimmed)) return trimmed;

  // ③どちらでもない。
  return null;
}
