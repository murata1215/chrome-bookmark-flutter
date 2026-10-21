import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// 未ペアリング時の「ペアリングのやり方」ガイド。
///
/// Chrome 拡張を PC に入れたことが無いユーザーは、8桁コード/QR を
/// どこから出すのか分からない（`PairingScreen` の説明文だけでは伝わらない）。
/// 実機スクショ（`tool/gen_guide_images.py` で加工済み。識別子マスク・QR 無効化済み）
/// を使い、操作順に沿って見せる。
class PairingGuideScreen extends StatelessWidget {
  const PairingGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ペアリングのやり方')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: const [
            Text(
              'PC の Chrome 拡張機能でコードを発行し、このアプリで読み取ってペアリングします。',
            ),
            SizedBox(height: 24),
            _GuideStep(
              number: '1',
              title: 'PC の Chrome に拡張機能を入れる',
              body: 'Chrome ウェブストアから「Chrome Bookmark Launcher」拡張機能を'
                  'インストールしてください。',
            ),
            SizedBox(height: 28),
            _GuideStep(
              number: '2',
              title: '拡張機能を開く',
              body: 'ツールバーの拡張機能アイコン（パズルのピース）をタップし、\n'
                  '一覧から「Chrome Bookmark Launcher」を選びます。',
              imageAsset: 'assets/guide/step1_extensions.png',
              imageAspectRatio: 576 / 732,
            ),
            SizedBox(height: 28),
            _GuideStep(
              number: '3',
              title: '「スマホとペアリング」を押す',
              body: '拡張機能のパネルが開いたら、「スマホとペアリング」をタップします。',
              imageAsset: 'assets/guide/step2_popup.png',
              imageAspectRatio: 507 / 717,
            ),
            SizedBox(height: 28),
            _GuideStep(
              number: '4',
              title: 'QR コードを読み取る',
              body: '表示された QR コードを、このアプリの「QRコードを読み取る」で読み取る'
                  'か、8桁のコードを手入力してください。\n'
                  '有効期限は発行から約5分です。',
              imageAsset: 'assets/guide/step3_qr_sample.png',
              imageAspectRatio: 517 / 558,
              imageCaption: '※ 実際の画面イメージです（この QR 自体は読み取れません）',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  final String? imageAsset;
  final double? imageAspectRatio;
  final String? imageCaption;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.body,
    this.imageAsset,
    this.imageAspectRatio,
    this.imageCaption,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: s.primary, shape: BoxShape.circle),
              child: Text(
                number,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: s.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: s.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (imageAsset != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                // スクショは PC 側の白い画面なので、ダークモードでもあえて白いまま
                // 見せる（テーマに馴染ませようとせず「これは PC の画面です」と
                // 分かる見せ方にする）。枠線だけテーマに合わせる。
                decoration: BoxDecoration(
                  border: Border.all(color: s.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: AspectRatio(
                  aspectRatio: imageAspectRatio ?? 1,
                  child: Image.asset(imageAsset!, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          if (imageCaption != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                imageCaption!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: s.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
