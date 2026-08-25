// TODO: M3E Migration - 对话框/对话框/消息条（AlertDialog/SnackBar）：m3e_core 1.1.0 未提供
// 对应实现，按迁移规则 3 暂用官方 material 最新组件，等官方 M3E 包覆盖后二次迁移。
//
// TODO: M3E Migration - ListView：等 m3e_design 提供列表页布局后再评估 M3ECardList。
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'log_collector.dart';

enum _LogAction { save, send }

/// 弹出日志处理对话框：选择「保存日志」或「发送日志」。
Future<void> showLogDialog(BuildContext context) async {
  final action = await showDialog<_LogAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导出日志'),
      content: const Text('请选择日志的处理方式，日志会先压缩为 zip 文件。'),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        M3EFilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(_LogAction.save),
          child: const Text('保存日志'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(_LogAction.send),
          child: const Text('发送日志'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;

  // 处理期间显示进度
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: M3ECircularProgressIndicator()),
  );

  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (action) {
      case _LogAction.save:
        final path = await _pickSavePath();
        if (path == null) return; // 用户取消保存位置
        final zip = await LogCollector.instance.exportZip(destPath: path);
        messenger.showSnackBar(
          SnackBar(content: Text('日志已保存到 ${zip.path}')),
        );
      case _LogAction.send:
        final zip = await LogCollector.instance.exportZip();
        await _shareZip(zip);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
  } finally {
    if (context.mounted) Navigator.of(context).pop(); // 关闭进度框
  }
}

/// 让用户选择 zip 的保存位置（桌面端与移动端均支持）。
Future<String?> _pickSavePath() async {
  final name = 'miga_logs_${DateTime.now().millisecondsSinceEpoch}.zip';
  try {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存日志',
      fileName: name,
    );
    if (result != null) return result;
  } catch (_) {}
  // 回退：保存到下载目录
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) return '${dir.path}/$name';
  } catch (_) {}
  return null;
}

/// 调用系统分享发送 zip；桌面端不支持分享时回退为打开文件所在位置。
Future<void> _shareZip(File zip) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        text: 'MIGA-谜咖 应用日志',
      ),
    );
  } catch (_) {
    // 桌面端（如 Linux）无系统分享，打开文件管理器/默认应用以便手动分享
    await launchUrl(Uri.file(zip.path), mode: LaunchMode.externalApplication);
  }
}
