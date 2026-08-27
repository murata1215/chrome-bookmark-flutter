import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/prefs.dart';
import 'core/storage/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await AppPrefs.create();
  final overrides = <Override>[prefsProvider.overrideWithValue(prefs)];

  // `path_provider`（延いては dart:io の File 操作）は web 未対応のため、
  // `-d chrome` での UI 高速確認を潰さないようここだけガードする。
  Directory? directory;
  String? token;
  if (!kIsWeb) {
    directory = await getApplicationSupportDirectory();
    overrides.add(appDirectoryProvider.overrideWithValue(directory));
    token = await TokenStore().read();
  }

  final container = ProviderContainer(overrides: overrides);

  if (!kIsWeb) {
    // 起動時の一括読み込み（marks.json は小さいので初回フレームを速くできる。
    // snapshot のパース・平坦化は LocalStore 内で Isolate 化済み）。
    final localStore = container.read(localStoreProvider);
    final bundle = await localStore.loadAll();
    container.read(marksProvider.notifier).setAll(bundle.marks);
    container.read(pendingProvider.notifier).setAll(bundle.pending);
    container.read(snapshotProvider.notifier).setAll(bundle.snapshot, bundle.flat);
    container.read(authProvider.notifier).restore(token);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ChromeBookmarkApp(),
    ),
  );
}
