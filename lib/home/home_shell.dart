import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/sync/sync_service.dart';
import '../widgets/search_field.dart';
import 'frequency_tab.dart';
import 'home_providers.dart';
import 'library_tab.dart';
import 'search_results_view.dart';
import 'starred_tab.dart';

/// 3タブ（ライブラリ/お気に入り/頻度）＋検索。§6.3。
/// ライブラリタブはさらにカテゴリ一覧⇄ツリーを内部で切り替える（§U 追補）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index;

  static const _tabs = [
    _TabSpec(label: 'ブックマーク', icon: Icons.bookmarks_outlined, selectedIcon: Icons.bookmarks),
    _TabSpec(label: 'お気に入り', icon: Icons.star_border, selectedIcon: Icons.star),
    _TabSpec(label: '頻度', icon: Icons.trending_up_outlined, selectedIcon: Icons.trending_up),
  ];

  @override
  void initState() {
    super.initState();
    // §6.3: 初回起動時のデフォルトタブはお気に入り（index 1）。以降は前回位置へ復帰。
    _index = ref.read(prefsProvider).lastTabIndex ?? 1;
    // 起動直後の初回ロード。throttle を無視して強制的に叩く（§9「起動500ms」の
    // 順序どおり、初回フレーム後に投げるだけで描画はキャッシュ済みデータで先に出る）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).pullBookmarks(force: true);
    });
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    ref.read(prefsProvider).setLastTabIndex(i);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final searching = query.trim().isNotEmpty;
    // ライブラリタブでツリーの中に潜っているかどうか（戻るキーの挙動制御用）。
    final libraryPath = ref.watch(currentFolderProvider);
    final inTree = !searching && _index == 0 && libraryPath != null;

    return PopScope(
      canPop: !inTree,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ツリーの中なら1階層戻る（ルート直下からはカテゴリ一覧へ）。
        ref.read(currentFolderProvider.notifier).up();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          toolbarHeight: 60,
          scrolledUnderElevation: 2,
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SearchField(
              onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
        ),
        body: searching
            ? const SearchResultsView()
            : IndexedStack(
                index: _index,
                children: const [
                  LibraryTab(),
                  StarredTab(),
                  FrequencyTab(),
                ],
              ),
        bottomNavigationBar: searching
            ? null
            : NavigationBar(
                height: 64,
                selectedIndex: _index,
                onDestinationSelected: _selectTab,
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label,
                    ),
                ],
              ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _TabSpec({required this.label, required this.icon, required this.selectedIcon});
}
