import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 应用日志收集：接管 debugPrint、print、Flutter 错误与未捕获异常，
/// 写入本地日志文件，并支持把日志压缩成 zip 导出。
class LogCollector {
  LogCollector._();

  static final LogCollector instance = LogCollector._();

  static const _maxBufferLines = 10000;

  final List<String> _buffer = [];
  File? _file;
  Future<void> _queue = Future.value();

  /// 最近一次写入的原始行（用于去重 debugPrint→print 的双写）
  String? _lastRawLine;

  /// 初始化：创建日志文件，接管全局日志输出。应在 runApp 前调用。
  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logsDir = Directory('${dir.path}/logs');
      await logsDir.create(recursive: true);
      _file = File('${logsDir.path}/app.log');
    } catch (_) {
      _file = null;
    }

    // 会话头部：记录启动时间与平台信息，便于定位
    log(_deviceInfo());

    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.isNotEmpty) {
        _write(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _write('ERROR: ${details.exception}');
      _write('STACK: ${details.stack}');
      originalOnError?.call(details);
    };

    // 未捕获的 Dart 异常（含异步）
    final originalPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _write('FATAL: $error');
      _write('STACK: $stack');
      return originalPlatformError?.call(error, stack) ?? false;
    };
  }

  /// 应用级日志入口：供业务代码主动打点。
  void log(String message) {
    // 去重 debugPrint 内部调用 print() 导致的同一行双写
    if (message == _lastRawLine) return;
    _write(message);
  }

  /// 串行写入，避免并发写同一文件。
  void _write(String message) {
    _lastRawLine = message;
    final entry = '${DateTime.now().toIso8601String()} $message';
    _buffer.add(entry);
    if (_buffer.length > _maxBufferLines) {
      _buffer.removeAt(0);
    }
    final file = _file;
    if (file == null) return;
    _queue = _queue.then(
      (_) => file.writeAsString('$entry\n', mode: FileMode.append),
    );
  }

  String _deviceInfo() {
    final now = DateTime.now().toIso8601String();
    var os = 'unknown';
    var osVersion = '';
    try {
      os = Platform.operatingSystem;
      osVersion = Platform.operatingSystemVersion;
    } catch (_) {}
    final platform = defaultTargetPlatform.name;
    return '===== MIGA-谜咖 日志会话开始 =====\n'
        '时间: $now\n'
        '平台: $platform / $os ($osVersion)\n'
        '===== 会话开始 =====';
  }

  /// 把缓冲区的日志追加到文件。
  Future<void> _flush() async {
    final file = _file;
    if (file == null || _buffer.isEmpty) return;
    final chunk = _buffer.map((e) => '$e\n').join();
    _buffer.clear();
    _queue = _queue.then((_) => file.writeAsString(chunk, mode: FileMode.append));
    await _queue;
  }

  /// 把日志压缩为 zip。destPath 提供时写入该路径，否则写入临时目录。
  Future<File> exportZip({String? destPath}) async {
    List<int> content;
    final file = _file;
    if (file != null) {
      await _flush();
      content = file.existsSync() ? await file.readAsBytes() : <int>[];
    } else {
      // 日志文件不可用时（如测试环境），回退到内存缓冲
      content = utf8.encode(_buffer.map((e) => '$e\n').join());
    }
    final archive = Archive()
      ..add(ArchiveFile('app.log', content.length, content));
    final zipBytes = ZipEncoder().encode(archive);
    final name = 'miga_logs_${DateTime.now().millisecondsSinceEpoch}.zip';
    final path = destPath ?? '${(await getTemporaryDirectory()).path}/$name';
    final dest = File(path);
    await dest.writeAsBytes(zipBytes, flush: true);
    return dest;
  }
}
