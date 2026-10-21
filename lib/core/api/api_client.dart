import '../models/bookmarks_response.dart';
import '../models/device_info.dart';
import '../models/pending.dart';

/// API 呼び出し失敗を表す統一例外。
///
/// [statusCode] / [isJson] / [code] の3つで §0-4・§8 の判定ロジックを
/// そのまま表現できるようにしてある：
/// - `isUnauthorizedWipe` = ローカル全消去のトリガ（3条件 AND）
/// - `isServerPlaceholder` = 200 + text/html（Caddy の placeholder）。絶対にキャッシュを消さない
class ApiException implements Exception {
  final int? statusCode;
  final String code; // 'unauthorized' / 'invalid_code' / 'invalid_request' / 'rate_limited' /
  // 'payload_too_large' / 'not_found' / 'network_error' / 'timeout' / 'server_error' / 'unknown'
  final String message;
  final Duration? retryAfter; // 429 の Retry-After
  final bool isJson; // 応答の Content-Type が application/json だったか

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
    this.isJson = false,
  });

  /// §0-4・§8: ローカル全消去のトリガ（3条件 AND: 401 かつ JSON かつ unauthorized）。
  bool get isUnauthorizedWipe => statusCode == 401 && isJson && code == 'unauthorized';

  /// §0-4: 200 だが Content-Type が text/html（Caddy の placeholder＝サーバー障害）。
  /// 一時エラーとして扱い、キャッシュは消さない。
  bool get isServerPlaceholder => statusCode == 200 && !isJson;

  /// 4xx（429 を除く）は再試行しない。5xx・timeout・network はバックオフ対象。
  bool get isRetryable {
    if (code == 'network_error' || code == 'timeout' || code == 'server_error') return true;
    if (statusCode != null && statusCode! >= 500) return true;
    if (code == 'rate_limited') return true;
    return false;
  }

  @override
  String toString() => 'ApiException(code: $code, status: $statusCode, message: $message)';
}

/// サーバー API の抽象インターフェース。`HttpApiClient`（実サーバー）と
/// `MockApiClient`（インメモリ疑似サーバー）の両方がこれを実装する。
abstract class ApiClient {
  /// POST /pairing/claim
  /// 400 invalid_code（コード自体の存在/期限/使用済みは区別不可・意図的）、
  /// 400 invalid_request（形式不正）、429 rate_limited、413 payload_too_large を投げうる。
  Future<PairingClaimResponse> claimPairing({
    required String code,
    required String deviceName,
    required String platform,
  });

  /// GET /bookmarks
  /// [marksSince] は inclusive（省略時は初回として全件相当）。
  /// [treeHash] は `snapshot.json` の読み込みに成功した時だけ渡す
  /// （ファイル破損時に渡すと `roots:null` が返って永久に空表示になるため）。
  Future<BookmarksResponse> getBookmarks({
    required String deviceToken,
    DateTime? marksSince,
    String? treeHash,
  });

  /// POST /marks/open（1リクエスト最大200件を呼び出し側で守ること）。
  Future<OpenBatchResponse> postMarksOpen({
    required String deviceToken,
    required List<PendingOpen> opens,
  });

  /// PUT /marks/star（絶対値を送る冪等な操作）。
  Future<StarResponse> putMarksStar({
    required String deviceToken,
    required String url,
    required bool starred,
  });

  /// GET /device（未デプロイの間は 404 = ApiException(code: 'not_found')）。
  Future<DeviceInfoResponse> getDevice({required String deviceToken});

  /// PATCH /device（未デプロイの間は 404）。name は最大100文字。
  Future<void> patchDevice({required String deviceToken, required String name});

  /// DELETE /device（§ペアリング解除。この device_token のみを失効させる。
  /// 未デプロイの間は 404。冪等なので既に失効済みなら 401 が返る想定で、
  /// 呼び出し側 [AuthNotifier.unpairWithRevoke] はどちらも成功として扱う）。
  Future<void> revokeDevice({required String deviceToken});
}
