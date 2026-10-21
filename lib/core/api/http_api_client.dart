import 'package:dio/dio.dart';

import '../config.dart';
import '../models/bookmarks_response.dart';
import '../models/device_info.dart';
import '../models/pending.dart';
import 'api_client.dart';

/// 実サーバー向け REST 実装（P6・§5.3）。
///
/// `ApiException` へのマッピングが要点（§0-4・§8）:
/// - 401 wipe 判定（3条件 AND）と 200+text/html 判定は、どちらも
///   応答の `Content-Type` を見て [ApiException.isJson] を正しく立てられるか
///   どうかに懸かっている。
/// - `Retry-After` ヘッダは秒数として [ApiException.retryAfter] に変換する。
class HttpApiClient implements ApiClient {
  HttpApiClient({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: '${baseUrl ?? AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
          // ステータスに関わらず常に正常応答として受け取り、判定は自前で行う
          // （§0-4 の 200+text/html を DioException にしてしまうと判定できない）。
          validateStatus: (_) => true,
        ));

  final Dio _dio;

  Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  bool _isTimeout(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  /// dio 呼び出しを実行し、2xx以外・通信エラー・200+非JSONを
  /// [ApiException] へ統一的に変換する。成功時は生の [Response] を返す。
  Future<Response<dynamic>> _guard(Future<Response<dynamic>> Function() call) async {
    Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      if (_isTimeout(e)) {
        throw const ApiException(code: 'timeout', message: '通信がタイムアウトしました');
      }
      if (e.response == null) {
        throw const ApiException(code: 'network_error', message: 'ネットワークに接続できません');
      }
      response = e.response!;
    }

    final status = response.statusCode ?? 0;
    final contentType = response.headers.value('content-type') ?? '';
    final isJson = contentType.toLowerCase().contains('application/json');

    if (status >= 200 && status < 300) {
      // §0-4: 200 だが Content-Type が text/html（Caddy の placeholder）＝サーバー障害。
      // **`status == 200` の時だけ**チェックする。`204 No Content`（例:
      // `revokeDevice`）はボディが無いので Content-Type も付かないのが正常であり、
      // 全 2xx に広げると実際に成功した 204 応答まで誤って弾いてしまうため
      // （`ApiException.isServerPlaceholder` 自体も `statusCode == 200` 限定）。
      if (status == 200 && !isJson) {
        throw ApiException(
          code: 'server_placeholder',
          message: 'サーバーに接続できません',
          statusCode: status,
          isJson: false,
        );
      }
      return response;
    }

    var code = 'unknown';
    var message = '通信に失敗しました';
    final data = response.data;
    if (isJson && data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      code = (err['code'] as String?) ?? code;
      message = (err['message'] as String?) ?? message;
    } else if (status >= 500) {
      code = 'server_error';
    }

    Duration? retryAfter;
    final ra = response.headers.value('retry-after');
    final raSecs = ra == null ? null : int.tryParse(ra);
    if (raSecs != null) retryAfter = Duration(seconds: raSecs);

    throw ApiException(
      code: code,
      message: message,
      statusCode: status,
      isJson: isJson,
      retryAfter: retryAfter,
    );
  }

  @override
  Future<PairingClaimResponse> claimPairing({
    required String code,
    required String deviceName,
    required String platform,
  }) async {
    final resp = await _guard(() => _dio.post('/pairing/claim', data: {
          'code': code,
          'device_name': deviceName,
          'platform': platform,
        }));
    return PairingClaimResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<BookmarksResponse> getBookmarks({
    required String deviceToken,
    DateTime? marksSince,
    String? treeHash,
  }) async {
    final resp = await _guard(() => _dio.get(
          '/bookmarks',
          queryParameters: {
            'tree_hash': ?treeHash,
            'marks_since': ?marksSince?.toUtc().toIso8601String(),
          },
          options: _auth(deviceToken),
        ));
    return BookmarksResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<OpenBatchResponse> postMarksOpen({
    required String deviceToken,
    required List<PendingOpen> opens,
  }) async {
    final resp = await _guard(() => _dio.post(
          '/marks/open',
          data: {
            'events': opens
                .map((o) => {
                      'event_id': o.eventId,
                      'url': o.url,
                      'opened_at': o.openedAt.toUtc().toIso8601String(),
                    })
                .toList(),
          },
          options: _auth(deviceToken),
        ));
    return OpenBatchResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<StarResponse> putMarksStar({
    required String deviceToken,
    required String url,
    required bool starred,
  }) async {
    final resp = await _guard(() => _dio.put(
          '/marks/star',
          data: {'url': url, 'starred': starred},
          options: _auth(deviceToken),
        ));
    return StarResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<DeviceInfoResponse> getDevice({required String deviceToken}) async {
    final resp = await _guard(() => _dio.get('/device', options: _auth(deviceToken)));
    return DeviceInfoResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  @override
  Future<void> patchDevice({required String deviceToken, required String name}) async {
    await _guard(() => _dio.patch(
          '/device',
          data: {'name': name},
          options: _auth(deviceToken),
        ));
  }

  @override
  Future<void> revokeDevice({required String deviceToken}) async {
    await _guard(() => _dio.delete('/device', options: _auth(deviceToken)));
  }
}
