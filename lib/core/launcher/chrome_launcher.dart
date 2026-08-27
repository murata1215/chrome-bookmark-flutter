import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Chrome 起動の結果（設定画面のデバッグ行に表示するため enum 化。§7 の実機検証用）。
enum LaunchOutcome {
  /// Android: `AndroidIntent` で Chrome 系パッケージへ直接遷移できた。
  chromeIntent,

  /// iOS: `googlechrome(s):` スキームで Chrome アプリへ遷移できた。
  chromeScheme,

  /// Chrome 系が見つからず、既定のブラウザ等へ委譲した。
  fallback,

  /// 起動できなかった（http/https 以外、あるいは launch 自体が失敗）。
  unsupported,
}

/// Android で優先的に試す Chrome 系パッケージ（安定版 → ベータ → 開発版 → カナリア）。
/// `AndroidManifest.xml` の `<queries>` にも同じ4つを列挙してあること
/// （API 30+ は宣言が無いと `canResolveActivity()` が常に false を返す）。
const androidChromePackages = [
  'com.android.chrome',
  'com.chrome.beta',
  'com.chrome.dev',
  'com.chrome.canary',
];

/// `https://` → `googlechromes://`、`http://` → `googlechrome://` の書き換え。
///
/// **`Uri.replace(scheme:)` は使わない。** path/query を再正規化するため、
/// userinfo や IDN ホストを壊す可能性がある。生文字列の `replaceFirst` のみで
/// 書き換えることで、クエリ・フラグメントを含め残りの部分を一切変更しない。
///
/// http/https 以外は null（呼び出し側は他の手段にフォールバックする）。
String? iosChromeSchemeFor(String url) {
  if (url.startsWith('https://')) return url.replaceFirst('https://', 'googlechromes://');
  if (url.startsWith('http://')) return url.replaceFirst('http://', 'googlechrome://');
  return null;
}

/// Chrome 優先で URL を開く（§6.5）。http/https のみ対応。
///
/// **呼び出し側の責務（D-1・§6.5）**: この `open()` が
/// [LaunchOutcome.unsupported] 以外を返した時だけ、frecency イベント
/// （`opened_at` は事前にタップ時点で記録済みのものを使う）を記録・enqueue すること。
class ChromeLauncher {
  ChromeLauncher({TargetPlatform? platformOverride}) : _platformOverride = platformOverride;

  final TargetPlatform? _platformOverride;

  // Android の解決結果のセッションキャッシュ（binder 呼び出しを毎タップやらないため）。
  String? _resolvedAndroidPackage;
  bool _androidResolutionAttempted = false;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;

  Future<LaunchOutcome> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return LaunchOutcome.unsupported;
    }

    switch (_platform) {
      case TargetPlatform.android:
        return _openAndroid(url, uri);
      case TargetPlatform.iOS:
        return _openIOS(url, uri);
      default:
        return _openFallback(uri);
    }
  }

  Future<LaunchOutcome> _openAndroid(String url, Uri uri) async {
    if (!_androidResolutionAttempted) {
      _androidResolutionAttempted = true;
      for (final package in androidChromePackages) {
        try {
          final intent = AndroidIntent(action: 'action_view', data: url, package: package);
          final canResolve = await intent.canResolveActivity();
          if (canResolve == true) {
            _resolvedAndroidPackage = package;
            break;
          }
        } catch (_) {
          // 個別パッケージの解決失敗（プラグイン未初期化等）は無視して次を試す。
        }
      }
    }

    final resolved = _resolvedAndroidPackage;
    if (resolved != null) {
      try {
        await AndroidIntent(action: 'action_view', data: url, package: resolved).launch();
        return LaunchOutcome.chromeIntent;
      } catch (_) {
        // 起動に失敗した（アンインストールされた等）→ 以降はフォールバックへ切り替える。
        _resolvedAndroidPackage = null;
      }
    }

    return _openFallback(uri);
  }

  Future<LaunchOutcome> _openIOS(String url, Uri uri) async {
    final schemeUrl = iosChromeSchemeFor(url);
    if (schemeUrl != null) {
      final schemeUri = Uri.tryParse(schemeUrl);
      if (schemeUri != null) {
        try {
          if (await canLaunchUrl(schemeUri)) {
            final ok = await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
            if (ok) return LaunchOutcome.chromeScheme;
          }
        } catch (_) {
          // Chrome スキームでの起動に失敗 → 既定ブラウザへフォールバックする。
        }
      }
    }
    return _openFallback(uri);
  }

  Future<LaunchOutcome> _openFallback(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? LaunchOutcome.fallback : LaunchOutcome.unsupported;
    } catch (_) {
      return LaunchOutcome.unsupported;
    }
  }
}
