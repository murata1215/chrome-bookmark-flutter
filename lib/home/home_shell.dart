import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_tokens.dart';
import '../core/sync/sync_service.dart';
import '../widgets/search_field.dart';
import 'frequency_tab.dart';
import 'home_providers.dart';
import 'library_tab.dart';
import 'search_results_view.dart';
import 'starred_tab.dart';
import 'sync_error_banner.dart';

/// 3タブ（ライブラリ/お気に入り/頻度）＋検索。§6.3。
/// ライブラリタブはさらにカテゴリ一覧⇄ツリーを内部で切り替える（§U 追補）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    _TabSpec(label: 'ブックマーク', icon: Icons.bookmarks_outlined, selectedIcon: Icons.bookmarks),
    _TabSpec(label: 'お気に入り', icon: Icons.star_border, selectedIcon: Icons.star),
    _TabSpec(label: '頻度', icon: Icons.trending_up_outlined, selectedIcon: Icons.trending_up),
  ];

  @override
  void initState() {
    super.initState();
    // 起動直後の初回ロード。throttle を無視して強制的に叩く（§9「起動500ms」の
    // 順序どおり、初回フレーム後に投げるだけで描画はキャッシュ済みデータで先に出る）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).pullBookmarks(force: true);
    });
  }

  void _selectTab(int i) {
    HapticFeedback.selectionClick();
    ref.read(homeTabIndexProvider.notifier).select(i);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final searching = query.trim().isNotEmpty;
    final index = ref.watch(homeTabIndexProvider);
    // ライブラリタブでツリーの中に潜っているかどうか（戻るキーの挙動制御用）。
    final libraryPath = ref.watch(currentFolderProvider);
    final inTree = !searching && index == 0 && libraryPath != null;

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
        body: Column(
          children: [
            const SyncErrorBanner(),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.standard),
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.curveIn,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.985, end: 1.0).animate(
                      CurvedAnimation(parent: animation, curve: AppMotion.curve),
                    ),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(searching ? 'search' : 'tab$index'),
                  child: searching ? const SearchResultsView() : _tabAt(index),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: ClipRect(
          child: AnimatedAlign(
            duration: AppMotion.of(context, AppMotion.standard),
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            heightFactor: searching ? 0 : 1,
            child: AnimatedOpacity(
              duration: AppMotion.of(context, AppMotion.standard),
              opacity: searching ? 0 : 1,
              child: NavigationBar(
                height: 64,
                selectedIndex: index,
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
          ),
        ),
      ),
    );
  }

  Widget _tabAt(int index) {
    return switch (index) {
      0 => const LibraryTab(),
      1 => const StarredTab(),
      _ => const FrequencyTab(),
    };
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _TabSpec({required this.label, required this.icon, required this.selectedIcon});
}
