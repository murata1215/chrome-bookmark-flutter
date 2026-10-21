import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/folder_path.dart';

/// `shared_preferences` のラッパ。秘匿性の無い小さな状態のみを持つ
/// （device_token は token_store.dart、大きな JSON は各 *_store.dart）。
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPrefs> create() async => AppPrefs(await SharedPreferences.getInstance());

  static const _kLastTab = 'last_tab';
  static const _kLastFolder = 'last_folder';
  static const _kMarksSince = 'marks_since';
  static const _kClockOffsetMs = 'clock_offset_ms';
  static const _kLastBookmarksPullAt = 'last_bookmarks_pull_at';
  static const _kLastSyncAt = 'last_sync_at';
  static const _kDeviceName = 'device_name';
  static const _kEmail = 'email';
  static const _kFaviconEnabled = 'favicon_enabled';
  static const _kThemeMode = 'theme_mode';

  // --- ホーム画面: 前回のタブ・フォルダ位置（§6.3「再起動時に前回位置へ復帰」） ---

  int? get lastTabIndex => _prefs.getInt(_kLastTab);
  Future<void> setLastTabIndex(int index) => _prefs.setInt(_kLastTab, index);

  FolderPath? get lastFolder {
    final raw = _prefs.getString(_kLastFolder);
    if (raw == null) return null;
    try {
      final json = _decodeJsonMap(raw);
      return json == null ? null : FolderPath.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastFolder(FolderPath path) =>
      _prefs.setString(_kLastFolder, _encodeJsonMap(path.toJson()));

  Future<void> clearLastFolder() => _prefs.remove(_kLastFolder);

  // --- 同期カーソル（§5.3・§0-3: inclusive、60秒オーバーラップ込みの値を保存） ---

  DateTime? get marksSince {
    final raw = _prefs.getString(_kMarksSince);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> setMarksSince(DateTime value) =>
      _prefs.setString(_kMarksSince, value.toUtc().toIso8601String());

  Future<void> clearMarksSince() => _prefs.remove(_kMarksSince);

  // --- サーバー時計オフセット（offset = server_time − localNow）。|offset| > 24h は無視 ---

  Duration? get clockOffset {
    final ms = _prefs.getInt(_kClockOffsetMs);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> setClockOffset(Duration offset) async {
    if (offset.abs() > const Duration(hours: 24)) return;
    await _prefs.setInt(_kClockOffsetMs, offset.inMilliseconds);
  }

  /// 現在時刻にオフセットを加えた「サーバー相当」時刻。オフセット未取得ならローカル時刻。
  DateTime serverNow() {
    final offset = clockOffset;
    final now = DateTime.now().toUtc();
    return offset == null ? now : now.add(offset);
  }

  // --- GET /bookmarks の throttle（D-2: フォアグラウンド復帰では5分に1回まで） ---

  DateTime? get lastBookmarksPullAt {
    final raw = _prefs.getString(_kLastBookmarksPullAt);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> setLastBookmarksPullAt(DateTime value) =>
      _prefs.setString(_kLastBookmarksPullAt, value.toUtc().toIso8601String());

  bool shouldThrottlePull({DateTime? now}) {
    final last = lastBookmarksPullAt;
    if (last == null) return false;
    final n = now ?? DateTime.now().toUtc();
    return n.difference(last) < AppConfig.pullThrottle;
  }

  // --- 最終同期成功時刻（設定画面表示用） ---

  DateTime? get lastSyncAt {
    final raw = _prefs.getString(_kLastSyncAt);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> setLastSyncAt(DateTime value) =>
      _prefs.setString(_kLastSyncAt, value.toUtc().toIso8601String());

  // --- GET /device が 404 の間のフォールバック値（ペアリング時に保存） ---

  String? get deviceName => _prefs.getString(_kDeviceName);
  Future<void> setDeviceName(String name) => _prefs.setString(_kDeviceName, name);

  String? get email => _prefs.getString(_kEmail);
  Future<void> setEmail(String email) => _prefs.setString(_kEmail, email);

  // --- favicon 取得の ON/OFF（§7 との緊張関係。既定 OFF） ---

  bool get faviconEnabled => _prefs.getBool(_kFaviconEnabled) ?? AppConfig.faviconEnabledDefault;
  Future<void> setFaviconEnabled(bool enabled) => _prefs.setBool(_kFaviconEnabled, enabled);

  // --- テーマモード（0 = system, 1 = light, 2 = dark。既定 system） ---

  int get themeModeIndex => _prefs.getInt(_kThemeMode) ?? 0;
  Future<void> setThemeModeIndex(int index) => _prefs.setInt(_kThemeMode, index);

  // --- unpair 時の全消去 ---

  Future<void> clearAll() async {
    await Future.wait([
      _prefs.remove(_kLastTab),
      _prefs.remove(_kLastFolder),
      _prefs.remove(_kMarksSince),
      _prefs.remove(_kClockOffsetMs),
      _prefs.remove(_kLastBookmarksPullAt),
      _prefs.remove(_kLastSyncAt),
      _prefs.remove(_kDeviceName),
      _prefs.remove(_kEmail),
      // faviconEnabled はユーザー設定なので unpair でも保持する。
    ]);
  }

  static Map<String, dynamic>? _decodeJsonMap(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static String _encodeJsonMap(Map<String, dynamic> map) => jsonEncode(map);
}
