// P1/P3 のスモークテスト: 未ペアリング時はペアリング画面、
// デバッグバイパス後はホームシェル（3タブ）が表示されること。
//
// TokenStore はプラットフォームチャンネル（flutter_secure_storage）を叩くため、
// ウィジェットテストでは通信不要なフェイクに差し替える。
// prefsProvider / appDirectoryProvider / apiClientProvider も P3 で HomeShell が
// 起動直後に syncService.pullBookmarks() を叩くようになったため、
// UnimplementedError を避けるためテスト用の実体で override する。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chrome_bookmark_flutter/app.dart';
import 'package:chrome_bookmark_flutter/core/api/mock_api_client.dart';
import 'package:chrome_bookmark_flutter/core/api/mock_seed.dart';
import 'package:chrome_bookmark_flutter/core/providers.dart';
import 'package:chrome_bookmark_flutter/core/storage/prefs.dart';
import 'package:chrome_bookmark_flutter/core/storage/token_store.dart';

class _FakeTokenStore extends TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

void main() {
  testWidgets('未ペアリング時はペアリング画面、バイパス後はホームシェルが出る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.create();
    final dir = Directory.systemTemp.createTempSync('widget_test_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
          prefsProvider.overrideWithValue(prefs),
          appDirectoryProvider.overrideWithValue(dir),
          apiClientProvider.overrideWithValue(
            MockApiClient(seed: MockSeed.small(), delay: Duration.zero),
          ),
        ],
        child: const ChromeBookmarkApp(),
      ),
    );

    expect(find.text('ペアリング'), findsOneWidget);
    expect(find.text('デバッグ: 仮トークンでホームへ'), findsOneWidget);

    await tester.tap(find.text('デバッグ: 仮トークンでホームへ'));
    await tester.pumpAndSettle();

    // ホームシェル本体（NavigationBar の3タブ）が出ていること。タイトルは
    // 廃止済みなので検索欄で代用確認する（§U 追補: 一覧を広く見せるための刷新）。
    expect(find.text('ブックマーク'), findsOneWidget);
    expect(find.text('お気に入り'), findsOneWidget);
    expect(find.text('頻度'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // 左端タブ（ライブラリ）へ切り替え、初期状態はカテゴリ一覧（3ルート選択）であること。
    await tester.tap(find.text('ブックマーク'));
    await tester.pumpAndSettle();

    expect(find.text('ブックマーク バー'), findsOneWidget);
    expect(find.text('その他のブックマーク'), findsOneWidget);
    expect(find.text('モバイルのブックマーク'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });
}
