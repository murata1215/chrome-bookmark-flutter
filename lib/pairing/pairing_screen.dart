import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/mock_api_client.dart';
import '../core/device_name.dart';
import '../core/providers.dart';
import 'pairing_controller.dart';
import 'pairing_guide_screen.dart';
import 'pairing_scan_screen.dart';

/// ペアリング画面（§6.3 本実装: QR / 8桁コード入力）。
/// 成功すると `authProvider` が paired になり、`app.dart` のルーティングが
/// 自動的に `HomeShell` へ切り替わる。
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    defaultDeviceName().then((name) {
      if (mounted && _nameController.text.isEmpty) {
        setState(() => _nameController.text = name);
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(pairingControllerProvider.notifier).submit(
          rawCode: _codeController.text,
          deviceName: _nameController.text,
        );
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PairingScanScreen()),
    );
    if (code == null || !mounted) return;
    _codeController.text = code;
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(pairingControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ペアリング')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.primaryContainer],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.bookmark_rounded, size: 40, color: scheme.onPrimary),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Chrome のブックマークを手元に',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Chrome 拡張機能に表示された8桁のコードを入力するか、\nQRコードを読み取ってください。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PairingGuideScreen()),
                ),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('ペアリングのやり方を見る'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 9, // 8桁 + 区切りの空白1文字
                style: const TextStyle(fontSize: 24, letterSpacing: 2),
                inputFormatters: [_CodeInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'ペアリングコード',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '端末名',
                  counterText: '',
                ),
              ),
              if (uiState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  uiState.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: uiState.submitting ? null : _submit,
                child: uiState.submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ペアリングする'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: uiState.submitting ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QRコードを読み取る'),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      ref.read(authProvider.notifier).setPaired(MockApiClient.debugToken),
                  child: const Text('デバッグ: 仮トークンでホームへ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// コード入力欄を「1234 5678」形式にライブ整形する。
/// 常にカーソルを末尾に置く単純な実装（8桁のみの入力なので十分）。
class _CodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 4) buffer.write(' ');
      buffer.write(limited[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
