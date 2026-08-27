import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// ペアリング画面のデバイス名入力欄に最初から入れておく既定値。
/// 取得に失敗しても致命的ではないので、失敗時は固定文字列にフォールバックする。
Future<String> defaultDeviceName() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) return 'Web ブラウザ';
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final model = info.model;
      return model.isNotEmpty ? model : 'Android 端末';
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      final name = info.name;
      return name.isNotEmpty ? name : 'iOS 端末';
    }
  } catch (_) {
    // 端末情報が取れなくてもペアリングは続行できるようにする。
  }
  return 'この端末';
}
