import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_tokens.dart';
import '../core/sync/sync_service.dart';
import '../core/time_format.dart';

/// 同期失敗をホーム画面に常設で知らせるバナー。以前は `SyncStatus.lastError`
/// が設定画面でしか読まれておらず、ホームでは同期失敗が一切見えなかった。
///
/// `lastError` の生文字列（Dio の例外メッセージ等）はここでは出さない。
/// オフラインでもキャッシュで全機能が動くアプリなので、モーダルにせず
/// 操作を塞がない（AnimatedSize で高さが変わるだけ）。
class SyncErrorBanner extends ConsumerWidget {
  const SyncErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final s = context.scheme;

    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: !status.hasError
          ? const SizedBox(width: double.infinity)
          : Material(
              color: s.errorContainer,
              child: InkWell(
                onTap: () => ref.read(syncServiceProvider).syncNow(force: true),
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 18, color: s.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '同期できていません'
                            '${status.lastErrorAt != null ? '（${relativeJa(status.lastErrorAt!)}）' : ''}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: s.onErrorContainer),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.read(syncServiceProvider).syncNow(force: true),
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
