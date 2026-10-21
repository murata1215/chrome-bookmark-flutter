/// アプリ全体の設定値。ビルド時に --dart-define で上書き可能。
class AppConfig {
  /// API のベース URL（/api/v1 を含まないホスト部分）。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://chrome-bookmark.devrelay.io',
  );

  static const String apiPrefix = '/api/v1';

  /// モックモード。明示指定したときのみ有効。
  /// flutter run --dart-define=USE_MOCK=true
  static const bool useMock = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: false,
  );

  static bool get isMockActive => useMock || apiBaseUrl.isEmpty;

  /// モックの疑似オフラインモード（サーバー未接続の挙動を確認するため）。
  static const bool mockOffline = bool.fromEnvironment(
    'MOCK_OFFLINE',
    defaultValue: false,
  );

  /// GET /bookmarks を投げる最小間隔（フォアグラウンド復帰の度に叩かないため）。
  static const Duration pullThrottle = Duration(minutes: 5);

  /// pending flush の周期タイマー。
  static const Duration flushInterval = Duration(seconds: 30);

  /// favicon 取得の既定値。ホスト名のみ Google s2 favicons へ送信される（§7 との
  /// トレードオフ・設定画面でいつでも OFF に戻せる）。ユーザー要望によりカラー
  /// favicon 表示を優先し既定 ON。
  static const bool faviconEnabledDefault = true;

  /// 表示用バージョン文字列（pubspec.yaml の `version:` と手動で同期させる）。
  static const String displayVersion = '1.0.0';
}
