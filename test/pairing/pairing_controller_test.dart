import 'package:chrome_bookmark_flutter/core/api/mock_api_client.dart';
import 'package:chrome_bookmark_flutter/core/api/mock_seed.dart';
import 'package:chrome_bookmark_flutter/core/providers.dart';
import 'package:chrome_bookmark_flutter/core/storage/prefs.dart';
import 'package:chrome_bookmark_flutter/core/storage/token_store.dart';
import 'package:chrome_bookmark_flutter/pairing/pairing_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTokenStore extends TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

void main() {
  late ProviderContainer container;
  late MockApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.create();
    apiClient = MockApiClient(seed: MockSeed.small(), delay: Duration.zero);
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        prefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  group('PairingController.submit', () {
    test('形式不正（8桁でない）はサーバーを呼ばずに弾く', () async {
      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '123', deviceName: '端末A');

      expect(ok, isFalse);
      expect(container.read(pairingControllerProvider).errorMessage, '入力形式が正しくありません');
    });

    test('端末名が空なら弾く', () async {
      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '12345678', deviceName: '   ');

      expect(ok, isFalse);
      expect(container.read(pairingControllerProvider).errorMessage, '端末名を入力してください');
    });

    test('成功すると authProvider が paired になり prefs に保存される（空白混じりのコードも許容）', () async {
      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '1234 5678', deviceName: ' 端末A ');

      expect(ok, isTrue);
      expect(container.read(authProvider).isPaired, isTrue);
      expect(container.read(prefsProvider).deviceName, '端末A');
      final state = container.read(pairingControllerProvider);
      expect(state.submitting, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('invalid_code（00000000）は統一メッセージになる（区別不可・総当たり対策）', () async {
      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '00000000', deviceName: '端末A');

      expect(ok, isFalse);
      expect(
        container.read(pairingControllerProvider).errorMessage,
        'コードが無効か期限切れです。拡張機能で新しいコードを発行してください',
      );
    });

    test('429 rate_limited は Retry-After 秒数を表示する', () async {
      apiClient.fault = MockFault.rateLimited;

      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '12345678', deviceName: '端末A');

      expect(ok, isFalse);
      final state = container.read(pairingControllerProvider);
      expect(state.retryAfterSeconds, 30);
      expect(state.errorMessage, '30 秒後にもう一度お試しください');
    });

    test('通信エラーはラッチを消費しない（paired にならず一般エラーメッセージのみ）', () async {
      apiClient.fault = MockFault.offline;

      final ok = await container
          .read(pairingControllerProvider.notifier)
          .submit(rawCode: '12345678', deviceName: '端末A');

      expect(ok, isFalse);
      expect(container.read(authProvider).isPaired, isFalse);
      expect(container.read(pairingControllerProvider).errorMessage, isNotNull);
    });
  });
}
