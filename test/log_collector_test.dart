import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miga/utils/log_collector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 测试环境下避免真实平台通道，初始化会失败但应不影响收集
    await LogCollector.instance.init();
  });

  test('日志收集并压缩为 zip', () async {
    debugPrint('这是一条测试日志');
    debugPrint('另一条日志信息');
    final zip = await LogCollector.instance
        .exportZip(destPath: '${Directory.systemTemp.path}/test_logs.zip');
    expect(zip.existsSync(), isTrue);
    final bytes = zip.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.length, greaterThanOrEqualTo(1));
    final entry = archive.files.firstWhere((f) => f.name == 'app.log');
    final content = utf8.decode(entry.content as List<int>);
    expect(content, contains('这是一条测试日志'));
    expect(content, contains('另一条日志信息'));
  });
}
