import 'dart:io';

import 'package:chrome_bookmark_flutter/core/api/api_client.dart';
import 'package:chrome_bookmark_flutter/core/api/mock_api_client.dart';
import 'package:chrome_bookmark_flutter/core/models/bookmarks_response.dart';
import 'package:chrome_bookmark_flutter/core/models/device_info.dart';
import 'package:chrome_bookmark_flutter/core/models/pending.dart';
import 'package:chrome_bookmark_flutter/core/providers.dart';
import 'package:chrome_bookmark_flutter/core/storage/prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [ApiClient] を包み、`revokeDevice` だけ任意の例外に差し替えられる
/// テスト用ダブル（404/5xx 等、`MockApiClient` 単体では起こせない分岐を作る）。
class _FaultyRevokeClient implements ApiClient {
  _FaultyRevokeClient(this._inner, this._revokeException);

  final ApiClient _inner;
  final ApiException _revokeException;

  @override
  Future<void> revokeDevice({required String deviceToken}) async {
    throw _revokeException;
  }

  @override
  Future<PairingClaimResponse> claimPairing({
    required String code,
    required String deviceName,
    required String platform,
  }) =>
      _inner.claimPairing(code: code, deviceName: deviceName, platform: platform);

  @override
  Future<BookmarksResponse> getBookmarks({
    required String deviceToken,
    DateTime? marksSince,
    String? treeHash,
  }) =>
      _inner.getBookmarks(deviceToken: deviceToken, marksSince: marksSince, treeHash: treeHash);

  @override
  Future<OpenBatchResponse> postMarksOpen({
    required String deviceToken,
    required List<PendingOpen> opens,
  }) =>
      _inner.postMarksOpen(deviceToken: deviceToken, opens: opens);

  @override
  Future<StarResponse> putMarksStar({
    required String deviceToken,
    required String url,
    required bool starred,
  }) =>
      _inner.putMarksStar(deviceToken: deviceToken, url: url, starred: starred);

  @override
  Future<DeviceInfoResponse> getDevice({required String deviceToken}) =>
      _inner.getDevice(deviceToken: deviceToken);

  @override
  Future<void> patchDevice({required String deviceToken, required String name}) =>
      _inner.patchDevice(deviceToken: deviceToken, name: name);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('unpair_test_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> containerWith(ApiClient apiClient) async {
    final prefs = await AppPrefs.create();
    final container = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      prefsProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(apiClient),
    ]);
    return container;
  }

  group('AuthNotifier.unpairWithRevoke', () {
    test('成功（204相当）: サーバーから失効 → ローカルも消去', () async {
      final mock = MockApiClient();
      final container = await containerWith(mock);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);

      final outcome = await container.read(authProvider.notifier).unpairWithRevoke();

      expect(outcome, UnpairOutcome.revoked);
      expect(container.read(authProvider).isPaired, isFalse);
      // サーバー側でも token が失効していること（getDevice が 401 になる）。
      await expectLater(
        mock.getDevice(deviceToken: MockApiClient.debugToken),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('401（既に失効済み・冪等）: 成功扱いでローカルを消去', () async {
      final mock = MockApiClient();
      final container = await containerWith(mock);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);
      // 事前に一度失効させておき、2回目の revoke が 401 を引くようにする。
      await mock.revokeDevice(deviceToken: MockApiClient.debugToken);

      final outcome = await container.read(authProvider.notifier).unpairWithRevoke();

      expect(outcome, UnpairOutcome.alreadyRevoked);
      expect(container.read(authProvider).isPaired, isFalse);
    });

    test('404（サーバー未デプロイ）: ローカルは消去しつつ区別できる結果を返す', () async {
      final inner = MockApiClient();
      final faulty = _FaultyRevokeClient(
        inner,
        const ApiException(
          code: 'not_found',
          message: 'Not Found',
          statusCode: 404,
          isJson: false,
        ),
      );
      final container = await containerWith(faulty);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);

      final outcome = await container.read(authProvider.notifier).unpairWithRevoke();

      expect(outcome, UnpairOutcome.serverNotDeployed);
      expect(container.read(authProvider).isPaired, isFalse);
    });

    test('通信失敗: ローカルを消さず failed を返す（オフラインで詰ませない）', () async {
      final mock = MockApiClient()..fault = MockFault.offline;
      final container = await containerWith(mock);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);

      final outcome = await container.read(authProvider.notifier).unpairWithRevoke();

      expect(outcome, UnpairOutcome.failed);
      // ローカルは消えておらず、ペアリング状態も維持される（再試行できる）。
      expect(container.read(authProvider).isPaired, isTrue);
      expect(container.read(authProvider).deviceToken, MockApiClient.debugToken);
    });

    test('5xx（サーバーエラー）も failed としてローカルを消さない', () async {
      final mock = MockApiClient()..fault = MockFault.serverError;
      final container = await containerWith(mock);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);

      final outcome = await container.read(authProvider.notifier).unpairWithRevoke();

      expect(outcome, UnpairOutcome.failed);
      expect(container.read(authProvider).isPaired, isTrue);
    });
  });

  group('AuthNotifier.wipeAndUnpair（終端401ハンドラ用・既存仕様の回帰防止）', () {
    test('サーバー通信をせずローカルのみ消去する', () async {
      final mock = MockApiClient();
      final container = await containerWith(mock);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).setPaired(MockApiClient.debugToken);
      await container.read(authProvider.notifier).wipeAndUnpair();

      expect(container.read(authProvider).isPaired, isFalse);
      // wipeAndUnpair はサーバーに触れないので、token はまだサーバー上で有効なまま
      // （= getDevice が成功する）。unpairWithRevoke との違いを固定するための回帰テスト。
      final resp = await mock.getDevice(deviceToken: MockApiClient.debugToken);
      expect(resp.name, 'デバッグ端末');
    });
  });
}
