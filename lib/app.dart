import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/sync/lifecycle_sync.dart';
import 'core/theme.dart';
import 'home/home_shell.dart';
import 'pairing/pairing_screen.dart';

class ChromeBookmarkApp extends ConsumerWidget {
  const ChromeBookmarkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);
    // ルートで1回だけ生成・購読する（Provider は ProviderContainer の生存期間
    // ずっとキャッシュされるので、build が再実行されても再生成されない）。
    ref.watch(lifecycleSyncProvider);
    return MaterialApp(
      title: 'ブックマークランチャー',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: auth.isPaired ? const HomeShell() : const PairingScreen(),
    );
  }
}
