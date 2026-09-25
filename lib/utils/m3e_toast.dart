import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

/// 统一的「toast」提示：M3E 模态底部弹层（替代 SnackBar）。
///
/// 用法：`await showMigaToast(context, '已复制到剪贴板');`
Future<void> showMigaToast(
  BuildContext context,
  String message, {
  String title = '提示',
}) {
  return showM3EModalBottomSheet<void>(
    context: context,
    builder: (context) => M3EBottomSheet(
      title: Text(title),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          shape: M3EButtonShape.round,
          size: M3EButtonSize.sm,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, size: 20),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            M3EButton(
              style: M3EButtonStyle.filled,
              size: M3EButtonSize.sm,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    ),
  );
}
