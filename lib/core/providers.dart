import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/http_api_client.dart';
import 'api/mock_api_client.dart';
import 'api/mock_seed.dart';
import 'config.dart';
import 'frecency.dart';
import 'launcher/chrome_launcher.dart';
import 'models/bookmark_snapshot.dart';
import 'models/flat_bookmark.dart';
import 'models/mark.dart';
import 'models/pending.dart';
import 'storage/local_store.dart';
import 'storage/prefs.dart';
import 'storage/token_store.dart';

/// main.dart が起動時に await した実体で override する Provider 群
/// （`prefs / tokenStore / apiClient / localStore` を「起動時 override」する
/// パターン。UI 側は `Provider<Directory>` 等が未初期化のまま読まれることが
/// 無いことを前提にできる）。

/// アプリのデータディレクトリ（`path_provider` の `getApplicationSupportDirectory`）。
/// main.dart で override 必須。
final appDirectoryProvider = Provider<Directory>((ref) {
  throw UnimplementedError('appDirectoryProvider は main.dart で override すること');
});

final prefsProvider = Provider<AppPrefs>((ref) {
  throw UnimplementedError('prefsProvider は main.dart で override すること');
});

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// ライト/ダーク/システムの表示モード。設定画面の `SegmentedButton` から変更する。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values[ref.read(prefsProvider).themeModeIndex];

  void select(ThemeMode mode) {
    state = mode;
    ref.read(prefsProvider).setThemeModeIndex(mode.index);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore(ref.watch(appDirectoryProvider)));

/// Chrome 起動（§6.5）。Android の解決結果をセッション内でキャッシュするため、
/// アプリ内で単一のインスタンスを共有する。
final chromeLauncherProvider = Provider<ChromeLauncher>((ref) => ChromeLauncher());

/// `ApiClient` の実体。`USE_MOCK=true`（または `apiBaseUrl` 未設定）のときは
/// インメモリ疑似サーバー、それ以外は実サーバー実装（`HttpApiClient`）。
final apiClientProvider = Provider<ApiClient>((ref) {
  if (AppConfig.isMockActive) {
    final client = MockApiClient(seed: MockSeed.medium());
    if (AppConfig.mockOffline) client.fault = MockFault.offline;
    return client;
  }
  return HttpApiClient();
});

// --- 認証状態（§8） ---

enum AuthStatus { paired, unauthenticated }

/// [AuthNotifier.unpairWithRevoke] の結果。設定画面がユーザーへの通知文言を
/// 出し分けるために使う。
enum UnpairOutcome {
  /// サーバー側で device_token を失効できた（ローカルも消去済み）。
  revoked,

  /// 401（既に失効済み・冪等）。実質成功として扱う（ローカルは消去済み）。
  alreadyRevoked,

  /// 404（`DELETE /device` がサーバー未デプロイ）。ローカルは消去したが、
  /// PC 側（拡張機能）の接続は残ったままの可能性がある。
  serverNotDeployed,

  /// 通信失敗・timeout・5xx 等。ローカルは**消去していない**
  /// （呼び出し側がユーザーに確認の上、必要ならローカルのみ `wipeAndUnpair()` を呼ぶ）。
  failed,
}

class AuthState {
  final AuthStatus status;
  final String? deviceToken;

  const AuthState._(this.status, this.deviceToken);

  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated, null);

  const AuthState.paired(String token) : this._(AuthStatus.paired, token);

  bool get isPaired => status == AuthStatus.paired;
}

/// 認証状態の唯一の情報源。30秒タイマーと同期スケジューラはこれを watch し、
/// `unauthenticated` になったら自分自身を cancel する（タイマー内で bool を
/// 見るだけでは発火し続けるので不十分）。
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.unauthenticated();

  /// アプリ起動時、secure storage から読めた token で初期化する。
  void restore(String? token) {
    state = token == null ? const AuthState.unauthenticated() : AuthState.paired(token);
  }

  Future<void> setPaired(String token) async {
    await ref.read(tokenStoreProvider).write(token);
    state = AuthState.paired(token);
  }

  /// 終端401（§0-4・§8 の3条件 AND）を受けたときの全消去。
  ///
  /// **サーバー通信は一切行わない。** 呼び出し元の token が既にサーバー側で
  /// 無効と判定された後の後始末専用（`sync_service.dart` の終端401ハンドラ）。
  /// ユーザーの「ペアリングを解除」操作からは [unpairWithRevoke] を使うこと
  /// （こちらを直接呼ぶと device_token がサーバーに残ったままになる）。
  Future<void> wipeAndUnpair() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(localStoreProvider).clearAll();
    await ref.read(prefsProvider).clearAll();
    ref.read(marksProvider.notifier).setAll(const {});
    ref.read(pendingProvider.notifier).setAll(PendingQueue.empty);
    ref.read(snapshotProvider.notifier).setAll(null, const []);
    state = const AuthState.unauthenticated();
  }

  /// ユーザー操作（設定画面「ペアリングを解除」）用。`DELETE /device` で
  /// サーバー側の device_token を先に失効させてから、ローカルを消去する。
  ///
  /// 通信に失敗した場合（[UnpairOutcome.failed]）は**ローカルを消さない**。
  /// 呼び出し側（設定画面）がユーザーに確認を取り、それでもローカルだけ消したい
  /// 場合は [wipeAndUnpair] を直接呼ぶこと（オフラインで詰ませないための設計・
  /// 追補4 §失敗時の扱い）。
  Future<UnpairOutcome> unpairWithRevoke() async {
    final token = state.deviceToken;
    if (token == null) {
      await wipeAndUnpair();
      return UnpairOutcome.revoked;
    }
    try {
      await ref.read(apiClientProvider).revokeDevice(deviceToken: token);
      await wipeAndUnpair();
      return UnpairOutcome.revoked;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // 既に失効済み（冪等）。実質成功として扱う。
        await wipeAndUnpair();
        return UnpairOutcome.alreadyRevoked;
      }
      if (e.statusCode == 404) {
        // DELETE /device がサーバー未デプロイ。ローカルだけ消し、
        // PC 側の接続が残りうる旨は呼び出し側（UI）で伝える。
        await wipeAndUnpair();
        return UnpairOutcome.serverNotDeployed;
      }
      // network_error / timeout / server_error / rate_limited 等。
      return UnpairOutcome.failed;
    } catch (_) {
      return UnpairOutcome.failed;
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// --- 確定層: marks.json（サーバー応答のみを反映） ---

class MarksNotifier extends Notifier<Map<String, Mark>> {
  @override
  Map<String, Mark> build() => const {};

  void setAll(Map<String, Mark> marks) => state = marks;

  /// サーバー応答の反映。`updated_at` が保存値以上のときだけ適用する
  /// （★応答が open 応答より後に届いて新しいスコアを潰すのを防ぐ）。
  /// `title` はクライアント専用なので既存値を引き継ぐ。
  void mergeFromServer(Iterable<Mark> incoming) {
    final next = Map<String, Mark>.from(state);
    for (final m in incoming) {
      final existing = next[m.url];
      if (existing == null || !m.updatedAt.isBefore(existing.updatedAt)) {
        next[m.url] = m.withTitle(existing?.title);
      }
    }
    state = next;
  }

  /// スナップショットから補完した `titleByUrl` を確定層へ書き戻す（永続化用）。
  /// 戻り値は変更の有無（呼び出し側が保存要否を判断するため・§X2）。
  bool applyTitles(Map<String, String> titleByUrl) {
    if (titleByUrl.isEmpty) return false;
    final next = Map<String, Mark>.from(state);
    var changed = false;
    for (final entry in titleByUrl.entries) {
      final existing = next[entry.key];
      if (existing != null && existing.title != entry.value) {
        next[entry.key] = existing.withTitle(entry.value);
        changed = true;
      }
    }
    if (changed) state = next;
    return changed;
  }
}

final marksProvider = NotifierProvider<MarksNotifier, Map<String, Mark>>(MarksNotifier.new);

// --- 保留層: pending.json（未送信の open / ★変更） ---

class PendingNotifier extends Notifier<PendingQueue> {
  static const _maxOpens = 2000;

  @override
  PendingQueue build() => PendingQueue.empty;

  void setAll(PendingQueue queue) => state = queue;

  void enqueueOpen(PendingOpen open) {
    final opens = [...state.opens, open];
    final trimmed = opens.length > _maxOpens
        ? opens.sublist(opens.length - _maxOpens) // 古い方から破棄（寄与が小さいため）
        : opens;
    state = PendingQueue(opens: trimmed, stars: state.stars);
  }

  /// ON→OFF→ON は1件に潰れる（URL キーの上書き）。
  void enqueueStar(PendingStar star) {
    final stars = {...state.stars, star.url: star};
    state = PendingQueue(opens: state.opens, stars: stars);
  }

  void removeOpens(Set<String> eventIds) {
    if (eventIds.isEmpty) return;
    state = PendingQueue(
      opens: state.opens.where((o) => !eventIds.contains(o.eventId)).toList(),
      stars: state.stars,
    );
  }

  /// flush 成功後に該当 star を取り除く。ただし送信中にユーザーがさらに
  /// 変更していたら（`changedAt` が送信時点より後なら）残す。
  void removeStarIfUnchanged(String url, DateTime sentChangedAt) {
    final current = state.stars[url];
    if (current == null) return;
    if (current.changedAt.isAfter(sentChangedAt)) return;
    final stars = {...state.stars}..remove(url);
    state = PendingQueue(opens: state.opens, stars: stars);
  }
}

final pendingProvider = NotifierProvider<PendingNotifier, PendingQueue>(PendingNotifier.new);

// --- スナップショット（ツリータブ・検索用） ---

class SnapshotState {
  final BookmarkSnapshot? snapshot;
  final List<FlatBookmark> flat;

  const SnapshotState({required this.snapshot, required this.flat});

  static const empty = SnapshotState(snapshot: null, flat: []);
}

class SnapshotNotifier extends Notifier<SnapshotState> {
  @override
  SnapshotState build() => SnapshotState.empty;

  void setAll(BookmarkSnapshot? snapshot, List<FlatBookmark> flat) {
    state = SnapshotState(snapshot: snapshot, flat: flat);
  }
}

final snapshotProvider = NotifierProvider<SnapshotNotifier, SnapshotState>(SnapshotNotifier.new);

/// スナップショット上の URL → タイトル。★/頻度タブのタイトル補完用（§X1）。
/// `Mark.title` はクライアント専用でサーバー応答に含まれないため、確定層への
/// 永続化（§X2）を待たずに表示側でも常に最新のスナップショットを優先する。
/// 重複 URL は先勝ち（`flattenSnapshot` の titleByUrl と同じ規則）。
final snapshotTitleByUrlProvider = Provider<Map<String, String>>((ref) {
  final flat = ref.watch(snapshotProvider).flat;
  final map = <String, String>{};
  for (final fb in flat) {
    if (fb.title.trim().isEmpty) continue;
    map.putIfAbsent(fb.url, () => fb.title);
  }
  return map;
});

// --- 表示値 = 確定層 ⊕ 保留層（読み出し時に replay） ---

/// オーバーレイ方式（§設計の中核）の実体。1イベントの寄与は常に確定層か
/// 保留層のどちらか片方だけに存在するため、単純に replay するだけで良い。
final effectiveMarksProvider = Provider<Map<String, Mark>>((ref) {
  final marks = ref.watch(marksProvider);
  final pending = ref.watch(pendingProvider);
  if (pending.isEmpty) return marks;

  // 端末時計が進んでいる場合にサーバーの確定値と食い違わないよう、pending の
  // opened_at は読み出しの都度 clampOpenedAt を通してから適用する（§0-2・D-1）。
  final serverNow = ref.watch(prefsProvider).serverNow();

  final result = Map<String, Mark>.from(marks);

  final opensByUrl = <String, List<PendingOpen>>{};
  for (final open in pending.opens) {
    opensByUrl.putIfAbsent(open.url, () => []).add(open);
  }
  for (final entry in opensByUrl.entries) {
    final sorted = [...entry.value]..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    var mark = result[entry.key] ?? Mark.empty(entry.key);
    for (final open in sorted) {
      mark = mark.applyLocalOpen(clampOpenedAt(open.openedAt, serverNow));
    }
    result[entry.key] = mark;
  }

  for (final entry in pending.stars.entries) {
    final existing = result[entry.key] ?? Mark.empty(entry.key);
    final star = entry.value;
    final starredAt = existing.starredAt ?? (star.starred ? star.changedAt : null);
    result[entry.key] = existing.copyWith(
      starred: star.starred,
      starredAt: starredAt,
      starredAtToNull: starredAt == null,
    );
  }

  return result;
});
