import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/providers.dart';

/// ペアリング画面の UI 状態。
class PairingUiState {
  final bool submitting;
  final String? errorMessage;
  final int? retryAfterSeconds; // 429 のときだけ非 null（§0-4）

  const PairingUiState({
    this.submitting = false,
    this.errorMessage,
    this.retryAfterSeconds,
  });
}

/// `POST /pairing/claim` を叩き、成功したら `authProvider` を paired にする。
class PairingController extends Notifier<PairingUiState> {
  @override
  PairingUiState build() => const PairingUiState();

  static bool isValidCodeFormat(String code) => RegExp(r'^\d{8}$').hasMatch(code);

  /// DB の CHECK 制約に合わせた platform 値。
  static String platformValue() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// 成功したら true。失敗時は [state.errorMessage] にメッセージをセットして false を返す。
  ///
  /// **通信エラー（`ApiException` 以外）はラッチを消費しない**（§6.3）:
  /// エラーメッセージだけ表示し、入力済みのコードはクリアしない
  /// （呼び出し側の `TextEditingController` はそのまま保持される）。
  Future<bool> submit({required String rawCode, required String deviceName}) async {
    final code = rawCode.replaceAll(RegExp(r'\s'), '');
    if (!isValidCodeFormat(code)) {
      state = const PairingUiState(errorMessage: '入力形式が正しくありません');
      return false;
    }
    final trimmedName = deviceName.trim();
    if (trimmedName.isEmpty) {
      state = const PairingUiState(errorMessage: '端末名を入力してください');
      return false;
    }

    state = const PairingUiState(submitting: true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final resp = await apiClient.claimPairing(
        code: code,
        deviceName: trimmedName,
        platform: platformValue(),
      );
      await ref.read(authProvider.notifier).setPaired(resp.deviceToken);
      final prefs = ref.read(prefsProvider);
      await prefs.setDeviceName(trimmedName);
      await prefs.setEmail(resp.email);
      state = const PairingUiState();
      return true;
    } on ApiException catch (e) {
      state = PairingUiState(
        errorMessage: _messageFor(e),
        retryAfterSeconds: e.code == 'rate_limited' ? e.retryAfter?.inSeconds : null,
      );
      return false;
    } catch (_) {
      state = const PairingUiState(errorMessage: '通信に失敗しました。もう一度お試しください');
      return false;
    }
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = const PairingUiState();
  }

  String _messageFor(ApiException e) {
    switch (e.code) {
      case 'invalid_code':
        // §0-4: 存在しない / 期限切れ / 使用済みは意図的に区別不可（総当たり対策）。
        return 'コードが無効か期限切れです。拡張機能で新しいコードを発行してください';
      case 'invalid_request':
        return '入力形式が正しくありません';
      case 'rate_limited':
        final s = e.retryAfter?.inSeconds;
        return s != null ? '$s 秒後にもう一度お試しください' : 'リクエストが多すぎます。しばらくしてからお試しください';
      case 'payload_too_large':
        return '入力内容が長すぎます';
      default:
        return '通信に失敗しました。もう一度お試しください';
    }
  }
}

final pairingControllerProvider =
    NotifierProvider<PairingController, PairingUiState>(PairingController.new);
