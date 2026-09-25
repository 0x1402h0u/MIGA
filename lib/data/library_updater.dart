import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'card_pool.dart';
import 'local_store.dart';
import '../utils/log_collector.dart';

/// 一次更新的结局
enum LibraryUpdateStatus {
  /// 拉到新版并已换掉本地牌库
  updated,

  /// 本地已经不比线上旧
  upToDate,

  /// 网络/内容有问题
  failed,

  /// 已经有一个更新在跑
  busy,
}

class LibraryUpdateResult {
  const LibraryUpdateResult(
    this.status, {
    this.version,
    this.count,
    this.message,
  });

  final LibraryUpdateStatus status;

  /// 相关版本号（updated 是新版本，upToDate 是本地版本）
  final String? version;

  /// 更新后导入的卡牌数量
  final int? count;

  /// failed 时的原因
  final String? message;
}

/// 牌库在线更新。
///
/// 逻辑：先读 CDN 上的 `version.json`，和本地版本比；线上更新才去拉
/// `main.json` 换掉本地牌库，并把新版本号一起落盘。
///
/// - 首次激活自动查一次（[checkOnFirstLaunch]，查过就不再自动查）
/// - 之后由配装页右上角菜单手动触发（[update]）
///
/// 两个调用方共用 [updating]：配装页左侧「牌库」区据此显示加载指示器。
class LibraryUpdater {
  LibraryUpdater._();

  static final LibraryUpdater instance = LibraryUpdater._();

  /// 本地默认牌库版本（没有导入过任何牌库时按它比）
  static const defaultVersion = '1.0.0';

  static const _base =
      'https://cdn.jsdelivr.net/gh/0x1402h0u/MIGA@main/Card%20Pile';
  static const _versionUrl = '$_base/version.json';
  static const _libraryUrl = '$_base/main.json';

  /// 正在更新
  final ValueNotifier<bool> updating = ValueNotifier<bool>(false);

  /// 本地当前版本
  String get localVersion => CardPool.instance.version ?? defaultVersion;

  /// 首次激活时自动比对一次。
  ///
  /// 只有真的问到服务器（不管有没有新版）才记「查过了」；离线失败时不记，
  /// 下次启动还会再试。
  Future<LibraryUpdateResult> checkOnFirstLaunch() async {
    if (await LocalStore.instance.isLibraryFirstCheckDone()) {
      return const LibraryUpdateResult(LibraryUpdateStatus.upToDate);
    }
    final result = await update();
    if (result.status != LibraryUpdateStatus.failed) {
      await LocalStore.instance.setLibraryFirstCheckDone();
    }
    return result;
  }

  /// 拉版本号 → 比本地 → 新的就整库换掉
  Future<LibraryUpdateResult> update() async {
    if (updating.value) {
      return const LibraryUpdateResult(LibraryUpdateStatus.busy);
    }
    updating.value = true;
    try {
      final remoteVersion = _parseVersion(await _get(_versionUrl));
      if (remoteVersion == null) {
        LogCollector.instance.log('牌库更新：版本文件内容无法识别');
        return const LibraryUpdateResult(
          LibraryUpdateStatus.failed,
          message: '版本文件内容无法识别',
        );
      }
      final local = localVersion;
      // 一张牌都没有（全新安装）：不受版本号限制直接拉，否则新用户会一直对着空牌库
      final bootstrapping = CardPool.instance.cards.isEmpty;
      LogCollector.instance.log(
        '牌库更新：本地 v$local${bootstrapping ? '（空库）' : ''}，线上 v$remoteVersion',
      );
      if (!bootstrapping && _compareVersions(remoteVersion, local) <= 0) {
        return LibraryUpdateResult(
          LibraryUpdateStatus.upToDate,
          version: local,
        );
      }

      final json = await _get(_libraryUrl);
      final count = CardPool.instance.importJson(json);
      // importJson 会按 main.json 自己的 version 字段走；这里以 version.json 为准
      CardPool.instance.setVersion(remoteVersion);
      await LocalStore.instance.saveLibrary(
        CardPool.instance.cards,
        version: remoteVersion,
      );
      LogCollector.instance.log('牌库更新：导入 $count 张，记为 v$remoteVersion');
      return LibraryUpdateResult(
        LibraryUpdateStatus.updated,
        version: remoteVersion,
        count: count,
      );
    } catch (e) {
      final message = _describe(e);
      LogCollector.instance.log('牌库更新失败：$message');
      return LibraryUpdateResult(
        LibraryUpdateStatus.failed,
        message: message,
      );
    } finally {
      updating.value = false;
    }
  }

  /// 取文本内容。
  ///
  /// 带时间戳是为了绕开 jsDelivr 的缓存：不然「检查更新」可能一直读到旧文件。
  Future<String> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final target = Uri.parse(
        '$url?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final request = await client.getUrl(target);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: target);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  /// version.json 支持 `{"version": "1.0.1"}`、`"1.0.1"`、甚至纯文本 `1.0.1`
  static String? _parseVersion(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) return _clean(decoded);
      if (decoded is num) return decoded.toString();
      if (decoded is Map) {
        for (final key in const ['version', 'Version', 'ver', 'v']) {
          final value = decoded[key];
          if (value != null) return _clean(value.toString());
        }
      }
    } catch (_) {
      // 不是 JSON：当纯文本版本号处理
      return _clean(text);
    }
    return null;
  }

  static String? _clean(String raw) {
    final text = raw.trim().replaceFirst(RegExp('^[vV]'), '');
    return text.isEmpty ? null : text;
  }

  /// a 比 b 新返回正数；按数字段比，"1.0.10" > "1.0.9"
  static int _compareVersions(String a, String b) {
    final left = _segments(a);
    final right = _segments(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  static List<int> _segments(String version) => version
      .split(RegExp(r'[^0-9]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => int.tryParse(part) ?? 0)
      .toList();

  static String _describe(Object error) {
    if (error is SocketException) return '网络不可用（${error.osError?.message ?? error.message}）';
    if (error is HttpException) return '服务器返回 ${error.message}';
    if (error is TimeoutException) return '请求超时';
    if (error is FormatException) return '牌库内容不是合法 JSON';
    return '$error';
  }
}
