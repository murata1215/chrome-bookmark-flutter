import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// `device_token` のみを保持する（他の秘匿すべき値は無い）。
/// Android のクラウド復元後は稀に例外を投げうるので、読み出しは
/// try/catch して「トークン無し」として扱う（§8）。
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'device_token';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      final v = await _storage.read(key: _key);
      return (v != null && v.isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // 書き込み失敗は上位でリトライ判断させる（ここでは黙って諦める）。
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // 削除失敗しても致命的ではない（次回 write で上書きされる）。
    }
  }
}
