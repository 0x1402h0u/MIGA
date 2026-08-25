import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/card_pool.dart';
import '../data/local_store.dart';

/// 通过文件选择器导入 JSON 牌库到全局 CardPool，并持久化到本地。
Future<void> importCardLibrary(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = result?.files.single.path;
  if (path == null) return;
  try {
    final content = await File(path).readAsString();
    final count = CardPool.instance.importJson(content);
    await LocalStore.instance.saveLibrary(CardPool.instance.cards);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $count 张卡牌')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }
}
