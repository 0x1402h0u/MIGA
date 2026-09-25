import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'clipboard_auto_fill.dart';
import 'local_store.dart';

/// 后台剪贴板监听（Android 原生前台服务 + 通知）的 Dart 侧封装。
///
/// Android 10+ 默认禁止后台读剪贴板，需要先给应用打开 READ_CLIPBOARD 这个 app-op：
///
///     adb shell appops set com.miga.android READ_CLIPBOARD allow
///
/// （或用 Shizuku 让 App 自己执行这条命令）。没打开时服务照跑、通知照在，
/// 但读不到内容 —— [canReadInBackground] 就是给设置页显示这个状态的。
class ClipboardWatchService {
  ClipboardWatchService._();

  static final ClipboardWatchService instance = ClipboardWatchService._();

  static const _channel = MethodChannel('miga/clipboard_watch');

  /// 开关（持久化）
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// 系统当前是否允许后台读剪贴板（READ_CLIPBOARD app-op 状态）
  final ValueNotifier<bool> canReadInBackground = ValueNotifier<bool>(true);

  AppLifecycleListener? _lifecycle;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 启动时恢复：开关是开的就把服务重新拉起来
  Future<void> load() async {
    if (!isSupported) return;
    enabled.value = await LocalStore.instance.isClipboardWatchEnabled();
    if (enabled.value) await _attach();
  }

  Future<void> setEnabled(bool value) async {
    if (!isSupported) return;
    enabled.value = value;
    await LocalStore.instance.setClipboardWatchEnabled(value);
    if (value) {
      await _attach();
      // 服务在原生侧异步启动，状态晚一拍才准
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refreshState();
      return;
    }
    await _invoke<bool>('stop');
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// 刷新「服务是否在跑」与「能否后台读」；服务被系统杀掉时自动重启
  Future<void> refreshState() async {
    if (!isSupported) return;
    canReadInBackground.value = await _invoke<bool>('canReadInBackground') ?? false;
    if (!enabled.value) return;
    final running = await _invoke<bool>('isRunning') ?? false;
    if (!running) await _invoke<bool>('start');
  }

  Future<void> _attach() async {
    await _invoke<bool>('start');
    await _invoke<bool>('requestNotificationPermission');
    _channel.setMethodCallHandler((call) async {
      // App 还活着时通知被点开：原生侧直接推事件过来
      if (call.method == 'loadRequested') {
        await ClipboardAutoFill.instance.loadNow();
      }
    });
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(_onResume()));
    await refreshState();
  }

  /// 回到前台：刷新状态，并处理「点通知进来」的载入请求（冷启动走这条）
  Future<void> _onResume() async {
    await refreshState();
    final pending = await _invoke<bool>('consumeLoadRequest') ?? false;
    if (pending) await ClipboardAutoFill.instance.loadNow();
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } catch (_) {
      // 平台没实现/被拒：当作没有这项能力
      return null;
    }
  }
}
