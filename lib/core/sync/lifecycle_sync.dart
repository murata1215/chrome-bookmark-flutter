import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../providers.dart';
import 'sync_service.dart';

/// フォアグラウンド復帰時の同期とバックグラウンド中の停止をまとめる（§6.6・§8）。
///
/// - `onResume`: `syncNow()`。`GET /bookmarks` 側は `prefs.shouldThrottlePull()`
///   （5分）で自動的に抑制されるので、**flush は毎回・pull は5分に1回**が
///   自然に成立する。
/// - フォアグラウンド中は 30秒 `Timer.periodic` で `flushPending()` のみを回す
///   （pull は throttle 任せで十分。毎回 syncNow を叩くと無駄な throttle 判定が
///   30秒ごとに走るだけなので flush 単体にする）。
/// - `authProvider` を listen し、`unauthenticated` になったら**タイマーを
///   自分で cancel** する（タイマーのコールバック内で bool を見るだけでは
///   キャンセル漏れの余地がある・§8）。
class LifecycleSync {
  LifecycleSync(this._ref) {
    _listener = AppLifecycleListener(
      onResume: _handleResume,
      onPause: _stopTimer,
      onHide: _stopTimer,
      onDetach: _stopTimer,
    );
    _authSubscription = _ref.listen<AuthState>(authProvider, (previous, next) {
      if (!next.isPaired) _stopTimer();
    });
    // アプリはフォアグラウンドで起動するため、生成された時点で
    // resume 相当の扱いにする（初回の flush 取りこぼしを防ぐ）。
    _handleResume();
  }

  final Ref _ref;
  late final AppLifecycleListener _listener;
  late final ProviderSubscription<AuthState> _authSubscription;
  Timer? _timer;

  void _handleResume() {
    if (!_ref.read(authProvider).isPaired) return;
    unawaited(_ref.read(syncServiceProvider).syncNow());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_ref.read(authProvider).isPaired) return;
    _timer = Timer.periodic(AppConfig.flushInterval, (_) {
      if (!_ref.read(authProvider).isPaired) {
        _stopTimer();
        return;
      }
      unawaited(_ref.read(syncServiceProvider).flushPending());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _stopTimer();
    _authSubscription.close();
    _listener.dispose();
  }
}

/// `app.dart` のルート付近で1回だけ watch する（`ref.onDispose` で確実に破棄）。
final lifecycleSyncProvider = Provider<LifecycleSync>((ref) {
  final service = LifecycleSync(ref);
  ref.onDispose(service.dispose);
  return service;
});
