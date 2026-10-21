import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/mock_api_client.dart';
import '../core/config.dart';
import '../core/models/device_info.dart';
import '../core/providers.dart';
import '../core/sync/sync_service.dart';
import '../core/time_format.dart';

/// 設定画面（§0-5・R3）。
///
/// - 端末名: `GET /device` が 200 なら実値、404 の間は `prefs.deviceName` を
///   フォールバック表示する。編集は `PATCH /device` を試み、404（未デプロイ）
///   の間は保存できない旨を案内するだけで例外を出さない。
/// - 最終同期時刻＋「今すぐ同期」（`syncNow(force: true)`）。
/// - favicon 取得の ON/OFF（既定 OFF・§7 との緊張関係）。
/// - ペアリング解除（確認ダイアログ → `wipeAndUnpair()`）。
/// - `kDebugMode` 限定で `MockApiClient.fault` の実行時トグル。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  DeviceInfoResultState _deviceState = const DeviceInfoResultState.loading();
  bool _syncing = false;
  bool _unpairing = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final auth = ref.read(authProvider);
    final token = auth.deviceToken;
    if (token == null) {
      setState(() => _deviceState = const DeviceInfoResultState.unavailable());
      return;
    }
    try {
      final resp = await ref.read(apiClientProvider).getDevice(deviceToken: token);
      if (!mounted) return;
      setState(() => _deviceState = DeviceInfoResultState.loaded(resp));
    } on ApiException {
      // GET /device が未デプロイ（404）等。フォールバック表示に切り替える。
      if (!mounted) return;
      setState(() => _deviceState = const DeviceInfoResultState.unavailable());
    } catch (_) {
      if (!mounted) return;
      setState(() => _deviceState = const DeviceInfoResultState.unavailable());
    }
  }

  Future<void> _editDeviceName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('端末名を変更'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(hintText: '端末名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == currentName) return;

    final auth = ref.read(authProvider);
    final token = auth.deviceToken;
    if (token == null) return;
    try {
      await ref.read(apiClientProvider).patchDevice(deviceToken: token, name: newName);
      await ref.read(prefsProvider).setDeviceName(newName);
      await _loadDeviceInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('端末名を変更しました')));
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在サーバー側が端末名の変更に対応していません')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('通信に失敗しました')));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).syncNow(force: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmUnpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ペアリングを解除しますか？'),
        content: const Text(
          'この端末に保存されたブックマークデータ・履歴は全て削除され、'
          'PC の Chrome 拡張機能からもこの端末の接続が切断されます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _unpairing = true);
    final outcome = await ref.read(authProvider.notifier).unpairWithRevoke();
    if (!mounted) return;

    switch (outcome) {
      case UnpairOutcome.revoked:
      case UnpairOutcome.alreadyRevoked:
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;

      case UnpairOutcome.serverNotDeployed:
        // ローカルは既に消去済み。ポップすると画面が破棄されるので、
        // SnackBar ではなく先にダイアログで案内してから戻る。
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('この端末の設定を削除しました'),
            content: const Text(
              '現在サーバー側の接続解除には対応していないため、'
              'PC の Chrome 拡張機能からも「切断」を行ってください。',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;

      case UnpairOutcome.failed:
        setState(() => _unpairing = false);
        final localOnly = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('サーバーに接続できませんでした'),
            content: const Text(
              'この端末のデータだけ削除しますか？\n'
              'PC 側の接続は残ります。後でオンライン時に改めて解除することをおすすめします。',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('この端末だけ削除'),
              ),
            ],
          ),
        );
        if (localOnly != true) return;
        await ref.read(authProvider.notifier).wipeAndUnpair();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    final deviceState = _deviceState;
    final name = deviceState.info?.name ?? prefs.deviceName ?? '(不明)';
    final email = deviceState.info?.email ?? prefs.email ?? '';
    final canEditName = deviceState.info != null; // GET /device が生きていれば PATCH も生きている想定

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: const Text('端末名'),
            subtitle: Text(name),
            trailing: canEditName ? const Icon(Icons.edit_outlined) : null,
            onTap: canEditName ? () => _editDeviceName(name) : null,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('メールアドレス'),
            subtitle: Text(email.isEmpty ? '(不明)' : email),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('最終同期'),
            subtitle: Text(_lastSyncSubtitle(prefs.lastSyncAt, syncStatus)),
            trailing: _syncing || syncStatus.isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '今すぐ同期',
                    onPressed: _syncNow,
                  ),
            onTap: _syncing ? null : _syncNow,
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: const Text('favicon を取得する'),
            subtitle: const Text('ブックマークしたサイトのホスト名が Google に送信されます'),
            value: prefs.faviconEnabled,
            onChanged: (value) async {
              await prefs.setFaviconEnabled(value);
              if (mounted) setState(() {});
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.brightness_6_outlined),
                    const SizedBox(width: 16),
                    const Text('表示モード'),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('システム')),
                    ButtonSegment(value: ThemeMode.light, label: Text('ライト')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('ダーク')),
                  ],
                  selected: {ref.watch(themeModeProvider)},
                  onSelectionChanged: (selection) =>
                      ref.read(themeModeProvider.notifier).select(selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (kDebugMode && AppConfig.isMockActive) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('デバッグ: 障害注入', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _DebugFaultTile(),
          ],
          const Divider(),
          ListTile(
            leading: Icon(Icons.link_off, color: Theme.of(context).colorScheme.error),
            title: Text('ペアリングを解除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            trailing: _unpairing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _unpairing ? null : _confirmUnpair,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('オープンソースライセンス'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'ブックマークランチャー',
              applicationVersion: AppConfig.displayVersion,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              'バージョン ${AppConfig.displayVersion}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  String _lastSyncSubtitle(DateTime? lastSyncAt, SyncStatus status) {
    if (status.hasError && status.lastError != null) return status.lastError!;
    if (lastSyncAt == null) return '未同期';
    return relativeJa(lastSyncAt);
  }
}

/// `GET /device` の読み込み結果。404（未デプロイ）とその他のエラーは区別せず
/// 「フォールバック表示」に倒す（サーバー側が追加され次第、自動的に実値へ切り替わる）。
class DeviceInfoResultState {
  final DeviceInfoResponse? info;
  final bool loading;

  const DeviceInfoResultState._({this.info, this.loading = false});

  const DeviceInfoResultState.loading() : this._(loading: true);
  const DeviceInfoResultState.unavailable() : this._();
  const DeviceInfoResultState.loaded(DeviceInfoResponse info) : this._(info: info);
}

class _DebugFaultTile extends ConsumerWidget {
  const _DebugFaultTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(apiClientProvider);
    if (client is! MockApiClient) return const SizedBox.shrink();

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          children: [
            for (final fault in MockFault.values)
              ListTile(
                dense: true,
                title: Text(_faultLabel(fault)),
                trailing: client.fault == fault ? const Icon(Icons.check) : null,
                onTap: () => setState(() => client.fault = fault),
              ),
          ],
        );
      },
    );
  }

  String _faultLabel(MockFault fault) {
    switch (fault) {
      case MockFault.none:
        return '正常';
      case MockFault.offline:
        return 'オフライン';
      case MockFault.unauthorizedJson:
        return '401（JSON・unauthorized）';
      case MockFault.htmlPlaceholder:
        return '200 + text/html（サーバー障害）';
      case MockFault.rateLimited:
        return '429（Retry-After）';
      case MockFault.serverError:
        return '500';
    }
  }
}
