import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/pairing_code.dart';

/// QR 読み取り画面。読み取れたペアリングコード（8桁）を [Navigator.pop] で返す。
///
/// カメラ権限拒否・エミュレータ等でカメラ映像が得られない場合は [MobileScanner.errorBuilder]
/// で手入力フォームに差し替える（§6.3「エラーにしない」。カメラ拒否を事前確認しない）。
class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key});

  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  // フレームレートで onDetect が発火するため、最初の await より前に
  // 同期的に立てるラッチ。setState ベースの bool では取りこぼす。
  bool _claimed = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_claimed) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = extractPairingCode(raw);
      if (code != null) {
        _claimed = true;
        unawaited(_controller.stop());
        if (mounted) Navigator.of(context).pop(code);
        return;
      }
    }
    // ③どのバーコードも一致しなければ何もせず読み取りを継続する
    //   （エミュレータのカメラで無関係な物が写っても無視するだけで良い）。
  }

  void _submitManual(String code) {
    if (_claimed) return;
    _claimed = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QRコードを読み取る')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) =>
                  _CameraErrorFallback(onManualCode: _submitManual),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _ScanHint(),
            ),
          ),
          // エミュレータのカメラは QR を写せないため、実機無しでも onDetect の
          // パイプラインを検証できるようにする（本番ビルドには含まれない）。
          if (kDebugMode)
            Positioned(
              right: 16,
              top: 16,
              child: FloatingActionButton.small(
                heroTag: 'pairing-debug-qr-inject',
                tooltip: 'デバッグ: QR相当を注入',
                onPressed: () => _onDetect(
                  const BarcodeCapture(
                    barcodes: [
                      Barcode(
                        rawValue:
                            'https://chrome-bookmark.devrelay.io/pair?code=12345678',
                      ),
                    ],
                  ),
                ),
                child: const Icon(Icons.bug_report),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanHint extends StatelessWidget {
  const _ScanHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '拡張機能に表示された QR コードを枠内に写してください',
        style: TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CameraErrorFallback extends StatefulWidget {
  final ValueChanged<String> onManualCode;
  const _CameraErrorFallback({required this.onManualCode});

  @override
  State<_CameraErrorFallback> createState() => _CameraErrorFallbackState();
}

class _CameraErrorFallbackState extends State<_CameraErrorFallback> {
  final _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() => _localError = '8桁の数字を入力してください');
      return;
    }
    widget.onManualCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 48),
              const SizedBox(height: 16),
              const Text(
                'カメラを使用できません。8桁のコードを直接入力してください。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: '8桁のコード',
                  errorText: _localError,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _submit, child: const Text('決定')),
            ],
          ),
        ),
      ),
    );
  }
}
