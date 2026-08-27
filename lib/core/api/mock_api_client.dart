import 'dart:async';

import '../frecency.dart';
import '../models/bookmark_snapshot.dart';
import '../models/bookmarks_response.dart';
import '../models/device_info.dart';
import '../models/mark.dart';
import '../models/pending.dart';
import 'api_client.dart';
import 'mock_seed.dart';

/// デバッグ画面から切り替える障害注入の種類。
enum MockFault { none, offline, unauthorizedJson, htmlPlaceholder, rateLimited, serverError }

/// インメモリ疑似サーバー。オフライン開発・障害注入・ユニットテスト・CI 用。
/// 1インスタンス＝1サーバー。`claimPairing` の度に新しい device_token を発行し、
/// 複数デバイスのペアリングも同時にシミュレートできる。
class MockApiClient implements ApiClient {
  MockApiClient({MockSeed? seed, this.delay = const Duration(milliseconds: 80)})
      : _snapshot = (seed ?? MockSeed.medium()).snapshot,
        _marks = {for (final m in (seed ?? MockSeed.medium()).marks) m.url: m} {
    // P1〜P3 の「デバッグ: 仮トークンでホームへ」バイパス用に固定トークンを
    // あらかじめ認証済みとして登録しておく（実サーバーには存在しない・モック専用）。
    final now = _serverNow;
    _devices[debugToken] = _DeviceRecord(
      name: 'デバッグ端末',
      platform: 'android',
      email: 'debug@example.com',
      pairedAt: now,
      lastSeenAt: now,
    );
  }

  /// ペアリング画面のデバッグバイパスボタンが使う固定 device_token。
  static const String debugToken = 'debug-bypass-token';

  // --- 障害注入（--dart-define だけでなく実行時トグルにするため public にしてある） ---
  MockFault fault = MockFault.none;
  Duration delay;
  Duration clockSkew = Duration.zero; // server_time = now + clockSkew
  int pageSize = 500; // has_more ページングのテスト用に小さくできる

  final BookmarkSnapshot _snapshot;
  final Map<String, Mark> _marks; // key: url
  final Map<String, _DeviceRecord> _devices = {}; // key: device_token
  final Set<String> _seenEventIds = {};
  int _tokenCounter = 0;

  DateTime get _serverNow => DateTime.now().toUtc().add(clockSkew);

  Future<void> _wait() async {
    if (delay > Duration.zero) await Future.delayed(delay);
  }

  void _throwIfFault() {
    switch (fault) {
      case MockFault.none:
        return;
      case MockFault.offline:
        throw const ApiException(code: 'network_error', message: 'ネットワークに接続できません');
      case MockFault.unauthorizedJson:
        throw const ApiException(
          code: 'unauthorized',
          message: '認証情報が無効です',
          statusCode: 401,
          isJson: true,
        );
      case MockFault.htmlPlaceholder:
        // §0-4: 200 だが Content-Type が text/html（Caddy の placeholder）。
        throw const ApiException(
          code: 'server_placeholder',
          message: 'サーバーに接続できません',
          statusCode: 200,
          isJson: false,
        );
      case MockFault.rateLimited:
        throw const ApiException(
          code: 'rate_limited',
          message: 'リクエストが多すぎます',
          statusCode: 429,
          isJson: true,
          retryAfter: Duration(seconds: 30),
        );
      case MockFault.serverError:
        throw const ApiException(
          code: 'server_error',
          message: 'サーバーエラー',
          statusCode: 500,
          isJson: true,
        );
    }
  }

  void _requireAuth(String deviceToken) {
    if (!_devices.containsKey(deviceToken)) {
      throw const ApiException(
        code: 'unauthorized',
        message: '認証情報が無効です',
        statusCode: 401,
        isJson: true,
      );
    }
  }

  @override
  Future<PairingClaimResponse> claimPairing({
    required String code,
    required String deviceName,
    required String platform,
  }) async {
    await _wait();
    _throwIfFault();
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      throw const ApiException(
        code: 'invalid_request',
        message: '入力形式が正しくありません',
        statusCode: 400,
        isJson: true,
      );
    }
    if (code == '00000000') {
      throw const ApiException(
        code: 'invalid_code',
        message: 'コードが無効か期限切れです。拡張機能で新しいコードを発行してください',
        statusCode: 400,
        isJson: true,
      );
    }
    _tokenCounter++;
    final token = 'mock-device-token-$_tokenCounter';
    final now = _serverNow;
    _devices[token] = _DeviceRecord(
      name: deviceName,
      platform: platform,
      email: 'mock-user@example.com',
      pairedAt: now,
      lastSeenAt: now,
    );
    return PairingClaimResponse(deviceToken: token, email: 'mock-user@example.com');
  }

  @override
  Future<BookmarksResponse> getBookmarks({
    required String deviceToken,
    DateTime? marksSince,
    String? treeHash,
  }) async {
    await _wait();
    _throwIfFault();
    _requireAuth(deviceToken);
    _devices[deviceToken]!.lastSeenAt = _serverNow;

    final sameHash = treeHash != null && treeHash == _snapshot.treeHash;

    final all = _marks.values
        .where((m) => marksSince == null || !m.updatedAt.isBefore(marksSince))
        .toList()
      ..sort((a, b) {
        final c = a.updatedAt.compareTo(b.updatedAt);
        return c != 0 ? c : a.url.compareTo(b.url);
      });

    final page = all.take(pageSize).toList();
    final hasMore = all.length > pageSize;

    return BookmarksResponse(
      treeHash: _snapshot.treeHash,
      roots: sameHash ? null : {for (final e in _snapshot.roots.entries) e.key: e.value.toJson()},
      snapshotUpdatedAt: _snapshot.updatedAt,
      marks: page,
      serverTime: _serverNow,
      hasMore: hasMore,
    );
  }

  @override
  Future<OpenBatchResponse> postMarksOpen({
    required String deviceToken,
    required List<PendingOpen> opens,
  }) async {
    await _wait();
    _throwIfFault();
    _requireAuth(deviceToken);
    _devices[deviceToken]!.lastSeenAt = _serverNow;

    var duplicates = 0;
    final touched = <Mark>[];
    for (final open in opens) {
      if (_seenEventIds.contains(open.eventId)) {
        duplicates++;
        continue;
      }
      _seenEventIds.add(open.eventId);
      final existing = _marks[open.url] ?? Mark.empty(open.url);
      // 実サーバーの挙動（§0-2）を模してここでもクランプする。
      final updated = existing.applyLocalOpen(clampOpenedAt(open.openedAt, _serverNow));
      _marks[open.url] = updated;
      touched.add(updated);
    }
    return OpenBatchResponse(
      accepted: touched.length,
      duplicates: duplicates,
      marks: touched,
      serverTime: _serverNow,
    );
  }

  @override
  Future<StarResponse> putMarksStar({
    required String deviceToken,
    required String url,
    required bool starred,
  }) async {
    await _wait();
    _throwIfFault();
    _requireAuth(deviceToken);
    _devices[deviceToken]!.lastSeenAt = _serverNow;

    final existing = _marks[url] ?? Mark.empty(url);
    final now = _serverNow;
    // starred_at は初回★時刻を据え置く（サーバーの COALESCE 相当）。
    // 一度も★されていなければ null のまま（OFF→ON→OFF で消えない）。
    final newStarredAt = existing.starredAt ?? (starred ? now : null);
    final updated = existing.copyWith(
      starred: starred,
      starredAt: newStarredAt,
      starredAtToNull: newStarredAt == null,
      updatedAt: now,
    );
    _marks[url] = updated;
    return StarResponse(mark: updated, serverTime: now);
  }

  @override
  Future<DeviceInfoResponse> getDevice({required String deviceToken}) async {
    await _wait();
    _throwIfFault();
    _requireAuth(deviceToken);
    final device = _devices[deviceToken]!;
    return DeviceInfoResponse(
      name: device.name,
      platform: device.platform,
      pairedAt: device.pairedAt,
      lastSeenAt: device.lastSeenAt,
      email: device.email,
      snapshotUpdatedAt: _snapshot.updatedAt,
      marksCount: _marks.length,
    );
  }

  @override
  Future<void> patchDevice({required String deviceToken, required String name}) async {
    await _wait();
    _throwIfFault();
    _requireAuth(deviceToken);
    if (name.isEmpty || name.length > 100) {
      throw const ApiException(
        code: 'invalid_request',
        message: '入力形式が正しくありません',
        statusCode: 400,
        isJson: true,
      );
    }
    _devices[deviceToken]!.name = name;
  }
}

class _DeviceRecord {
  _DeviceRecord({
    required this.name,
    required this.platform,
    required this.email,
    required this.pairedAt,
    required this.lastSeenAt,
  });

  String name;
  final String platform;
  final String email;
  final DateTime pairedAt;
  DateTime lastSeenAt;
}
