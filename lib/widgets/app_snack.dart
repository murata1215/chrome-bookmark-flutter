import 'package:flutter/material.dart';

/// アプリ共通の SnackBar ヘルパー。`SnackBarThemeData`（lib/core/theme.dart）に
/// 乗った上で、アイコン・エラー配色・アクションを統一する。
void showAppSnack(
  BuildContext context,
  String message, {
  IconData? icon,
  bool isError = false,
  SnackBarAction? action,
}) {
  final s = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: isError ? s.onErrorContainer : s.onInverseSurface),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? s.errorContainer : null,
        duration: const Duration(seconds: 2),
        action: action,
      ),
    );
}
