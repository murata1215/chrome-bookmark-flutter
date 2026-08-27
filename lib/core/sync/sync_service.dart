import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../frecency.dart';
import '../models/bookmark_node.dart';
import '../models/bookmark_snapshot.dart';
import '../models/flat_bookmark.dart';
import '../models/mark.dart';
import '../models/pending.dart';
import '../providers.dart';
import '../storage/prefs.dart';

/// 同期の進行状況（設定画面・ホームのリフレッシュ表示が watch する）。
enum SyncPhase { idle, syncing, error }

class SyncStatus {
  final SyncPhase phase;
  final String? lastError;
  final DateTime? lastErrorAt;

  const SyncStatus({this.phase = SyncPhase.idle, this.lastError, this.lastErrorAt});

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get hasError => phase == SyncPhase.error;
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  void setSyncing() => state = const SyncStatus(phase: SyncPhase.syncing);

  void setIdle() => state = const SyncStatus();

  void setError(String message) => state = SyncStatus(
        phase: SyncPhase.error,
        lastError: message,
        lastErrorAt: DateTime.now().toUtc(),
      );
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

/// `GET /bookmarks` の pull・pending の flush・両者をまとめた `syncNow` を持つ。
///
/// - `flushPending()`: ★を先に・逐次、open を200件ずつ・逐次で送信する（§6.4・§6.6）。
///   チャンク（またはstar）が1件失敗したら即座に中断する（途中に401が挟まると
///   キュー全体を焼くため）。各送信の成功直後に確定層へ反映してから
///   `pending.json` を永続化する。
/// - `pullBookmarks()`: ページング・カーソル前進・`tree_hash` 不一致時の再取得。
/// - `syncNow()`: flush → pull の順で1本にまとめた入口。lifecycle・手動更新・
///   起動時が全部ここを呼ぶ。5xx / timeout / 429 は上限付きバックオフ
///   （30s→1m→5m→15m、成功でリセット）で `syncNow` 自体が呼び出しを間引く。
///   終端401（3条件 AND）は `authProvider.wipeAndUnpair()` を呼ぶ。
class SyncService {
  SyncService(this._ref);

  final Ref _ref;
  bool _pulling = false;
  bool _flushing = false;

  static const int _maxOpenChunk = 200;
  static const Duration _staleOpenAge = Duration(days: 25); // §5.4: サーバーは30日で削除
  static const List<Duration> _backoffSteps = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  int _backoffLevel = -1; // -1 = バックオフ未発動
  DateTime? _nextAllowedAt;

  bool get isPulling => _pulling;
  bool get isFlushing => _flushing;

  /// flush → pull の順で1本にまとめた入口。
  ///
  /// [force] が true なら pull の throttle とバックオフの両方を無視する
  /// （手動「今すぐ同期」用）。
  Future<void> syncNow({bool force = false}) async {
    final auth = _ref.read(authProvider);
    if (!auth.isPaired) return;

    if (!force) {
      final until = _nextAllowedAt;
      if (until != null && DateTime.now().toUtc().isBefore(until)) {
        return; // バックオフ中は間引く
      }
    }

    _ref.read(syncStatusProvider.notifier).setSyncing();
    try {
      await flushPending();
      await pullBookmarks(force: force);
      _resetBackoff();
      _ref.read(syncStatusProvider.notifier).setIdle();
    } on ApiException catch (e) {
      await _handleSyncError(e);
    } catch (_) {
      _ref.read(syncStatusProvider.notifier).setError('通信に失敗しました。もう一度お試しください');
    }
  }

  Future<void> _handleSyncError(ApiException e) async {
    if (e.isUnauthorizedWipe) {
      // 終端401（§0-4・§8 の3条件 AND）: ローカル全消去してペアリング画面へ。
      await _ref.read(authProvider.notifier).wipeAndUnpair();
      _resetBackoff();
      _ref.read(syncStatusProvider.notifier).setIdle();
      return;
    }
    if (e.isServerPlaceholder) {
      // 200 + text/html（Caddy の placeholder）＝サーバー障害。キャッシュは絶対に消さない。
      _scheduleBackoff(e.retryAfter);
      _ref.read(syncStatusProvider.notifier).setError('サーバーに接続できません');
      return;
    }
    if (e.isRetryable) {
      // 5xx / timeout / network / 429。429 は retryAfter があれば優先。
      _scheduleBackoff(e.retryAfter);
      _ref.read(syncStatusProvider.notifier).setError(e.message);
      return;
    }
    // それ以外の4xx（401非wipe・404等）は再試行しない。
    _ref.read(syncStatusProvider.notifier).setError(e.message);
  }

  void _resetBackoff() {
    _backoffLevel = -1;
    _nextAllowedAt = null;
  }

  void _scheduleBackoff(Duration? retryAfter) {
    if (retryAfter != null) {
      _nextAllowedAt = DateTime.now().toUtc().add(retryAfter);
      return;
    }
    _backoffLevel = (_backoffLevel + 1).clamp(0, _backoffSteps.length - 1);
    _nextAllowedAt = DateTime.now().toUtc().add(_backoffSteps[_backoffLevel]);
  }

  /// 未送信の★変更・open イベントをサーバーへ送信する。
  ///
  /// ★を先に・逐次、open を200件ずつ・逐次で送る。**1件（1チャンク）でも
  /// 失敗したら即座に中断**する（例外はそのまま呼び出し側へ伝播する）。
  Future<void> flushPending() async {
    if (_flushing) return;
    final auth = _ref.read(authProvider);
    final token = auth.deviceToken;
    if (!auth.isPaired || token == null) return;

    _flushing = true;
    try {
      final apiClient = _ref.read(apiClientProvider);
      final prefs = _ref.read(prefsProvider);
      final localStore = _ref.read(localStoreProvider);

      // --- ★ を先に、URL ごとに逐次送信 ---
      // 送信中に別の変更が積まれることがあるので、送信開始時点のスナップショットで回す。
      final stars = Map<String, PendingStar>.from(_ref.read(pendingProvider).stars);
      for (final entry in stars.entries) {
        final url = entry.key;
        final star = entry.value;
        final resp = await apiClient.putMarksStar(deviceToken: token, url: url, starred: star.starred);
        _ref.read(marksProvider.notifier).mergeFromServer([resp.mark]);
        // 確定層に新規作成された mark にはタイトルが無いため、スナップショットから
        // 補完してから保存する（§X3。Chrome 側で削除される前にタイトルを確保）。
        _ref.read(marksProvider.notifier).applyTitles(_ref.read(snapshotTitleByUrlProvider));
        await localStore.marksStore.save(_ref.read(marksProvider));
        await _applyServerTime(prefs, resp.serverTime);
        // 送信中にユーザーがさらに変更していたら（changedAt が送信時点より後なら）残す。
        _ref.read(pendingProvider.notifier).removeStarIfUnchanged(url, star.changedAt);
        await localStore.pendingStore.save(_ref.read(pendingProvider));
      }

      // --- open を25日超は破棄してから200件ずつ・逐次送信 ---
      final serverNow = prefs.serverNow();
      final staleIds = _ref
          .read(pendingProvider)
          .opens
          .where((o) => serverNow.difference(o.openedAt) > _staleOpenAge)
          .map((o) => o.eventId)
          .toSet();
      if (staleIds.isNotEmpty) {
        _ref.read(pendingProvider.notifier).removeOpens(staleIds);
        await localStore.pendingStore.save(_ref.read(pendingProvider));
      }

      while (true) {
        final chunk = _ref.read(pendingProvider).opens.take(_maxOpenChunk).toList();
        if (chunk.isEmpty) break;
        // 端末時計が進んでいる場合にサーバーの確定値と食い違わないよう、送信直前に
        // clampOpenedAt を通す（§0-2・D-1。event_id/url は変えず openedAt のみ丸める）。
        final now = prefs.serverNow();
        final clamped = chunk
            .map((o) => PendingOpen(
                  eventId: o.eventId,
                  url: o.url,
                  openedAt: clampOpenedAt(o.openedAt, now),
                ))
            .toList();
        final resp = await apiClient.postMarksOpen(deviceToken: token, opens: clamped);
        if (resp.marks.isNotEmpty) {
          _ref.read(marksProvider.notifier).mergeFromServer(resp.marks);
          _ref.read(marksProvider.notifier).applyTitles(_ref.read(snapshotTitleByUrlProvider));
          await localStore.marksStore.save(_ref.read(marksProvider));
        }
        await _applyServerTime(prefs, resp.serverTime);
        _ref.read(pendingProvider.notifier).removeOpens(chunk.map((o) => o.eventId).toSet());
        await localStore.pendingStore.save(_ref.read(pendingProvider));
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _applyServerTime(AppPrefs prefs, DateTime? serverTime) async {
    if (serverTime == null) return;
    await prefs.setClockOffset(serverTime.difference(DateTime.now().toUtc()));
  }

  /// [force] が true なら throttle を無視する（初回起動・手動更新用）。
  Future<void> pullBookmarks({bool force = false}) async {
    if (_pulling) return;
    final auth = _ref.read(authProvider);
    final token = auth.deviceToken;
    if (!auth.isPaired || token == null) return;

    final prefs = _ref.read(prefsProvider);
    if (!force && prefs.shouldThrottlePull()) return;

    _pulling = true;
    try {
      final apiClient = _ref.read(apiClientProvider);
      // tree_hash は「読み込みに成功したスナップショット」がある時だけ送る
      // （壊れたファイルなのに prefs にハッシュだけ残っていると、
      //  roots:null が返り続けて永久に空表示になるのを防ぐ・§7）。
      final treeHash = _ref.read(snapshotProvider).snapshot?.treeHash;

      var since = prefs.marksSince;
      final gatheredMarks = <Mark>[];
      Map<String, dynamic>? rootsJson;
      // GET /bookmarks は必ず1回以上応答するので、ループを抜けた時点で
      // 両方とも必ず代入済み（DTO 側も non-nullable・§0-5）。
      late DateTime snapshotUpdatedAt;
      late DateTime serverTime;
      String respondedTreeHash = treeHash ?? '';

      while (true) {
        final resp = await apiClient.getBookmarks(
          deviceToken: token,
          marksSince: since,
          treeHash: treeHash,
        );
        respondedTreeHash = resp.treeHash;
        serverTime = resp.serverTime;
        snapshotUpdatedAt = resp.snapshotUpdatedAt;
        if (resp.roots != null) {
          rootsJson = resp.roots;
        }
        gatheredMarks.addAll(resp.marks);
        if (!resp.hasMore || resp.marks.isEmpty) break;
        since = resp.marks.last.updatedAt;
      }

      // スナップショット反映。
      if (rootsJson != null) {
        final roots = <String, BookmarkFolder>{};
        for (final entry in rootsJson.entries) {
          final v = entry.value;
          if (v is Map<String, dynamic>) {
            final node = BookmarkNode.fromJson(v);
            if (node is BookmarkFolder) roots[entry.key] = node;
          }
        }
        final snapshot = BookmarkSnapshot(
          treeHash: respondedTreeHash,
          roots: roots,
          updatedAt: snapshotUpdatedAt,
        );
        final flattened = flattenSnapshot(snapshot);
        _ref.read(snapshotProvider.notifier).setAll(snapshot, flattened.flat);
        await _ref.read(localStoreProvider).snapshotStore.save(snapshot);
      } else if (treeHash != null && respondedTreeHash != treeHash) {
        // ハッシュ不一致なのに roots が届かなかった（壊れたローカルファイル等）→
        // ハッシュ無しで無条件に再取得する。
        _pulling = false;
        await pullBookmarks(force: true);
        return;
      }

      // marks 反映。
      if (gatheredMarks.isNotEmpty) {
        _ref.read(marksProvider.notifier).mergeFromServer(gatheredMarks);
      }
      // スナップショット由来のタイトル補完は mergeFromServer の「後」に行う
      // （今回届いたばかりの mark にもタイトルを付けるため・§X2）。roots が
      // 返らなかった回（tree_hash 一致）でも in-memory の flat から補完する。
      final titlesChanged = _ref
          .read(marksProvider.notifier)
          .applyTitles(_ref.read(snapshotTitleByUrlProvider));
      if (gatheredMarks.isNotEmpty || titlesChanged) {
        await _ref.read(localStoreProvider).marksStore.save(_ref.read(marksProvider));
      }

      // カーソル前進: next = marks.isEmpty ? server_time : min(server_time, max(updated_at))。
      // 保存するのは next − 60秒（オーバーラップを残す・§0-3）。
      DateTime next = serverTime;
      if (gatheredMarks.isNotEmpty) {
        final maxUpdated =
            gatheredMarks.map((m) => m.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
        if (maxUpdated.isBefore(next)) next = maxUpdated;
      }
      await prefs.setMarksSince(next.subtract(const Duration(seconds: 60)));
      await prefs.setLastBookmarksPullAt(DateTime.now().toUtc());
      await prefs.setLastSyncAt(DateTime.now().toUtc());
      await prefs.setClockOffset(serverTime.difference(DateTime.now().toUtc()));
    } finally {
      _pulling = false;
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));
