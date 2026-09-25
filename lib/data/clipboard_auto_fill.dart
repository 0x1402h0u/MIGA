import 'dart:async';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../models/analyze_state.dart';
import 'local_store.dart';

/// 剪贴板自动填充：开着的时候盯着剪贴板，内容一变就按对局格式解析，
/// 解析成功就把结果推给可视页（[state]）；解析不了就静静跳过。
///
/// 自动模式为什么不报错：剪贴板里随时可能是别的东西（聊天、网址、验证码），
/// 每复制一次就弹一次「加载失败」是骚扰。要看具体哪一行不对，用可视页下拉刷新
/// （[checkNow] 的 manual 模式），那里会把原因说清楚。
///
/// Android 10+ 的系统限制：App 在后台读不到剪贴板，系统也不会把变化通知过来。
/// 所以两条腿走路：
///   1. 前台监听（clipboard_watcher，桌面端不受这个限制）；
///   2. 回到前台时补读一次 —— 覆盖「在游戏里复制 → 切回 MIGA」这个主路径。
/// 处理过的文本会记下来去重，同一份数据不会重复解析。
class ClipboardAutoFill with ClipboardListener {
  ClipboardAutoFill._();

  static final ClipboardAutoFill instance = ClipboardAutoFill._();

  /// 开关状态（持久化在 SharedPreferences；打开前必须先同意免责声明）
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// 最近一次成功解析出来的对局数据；可视页监听它来刷新自己。
  final ValueNotifier<AnalyzeState?> state = ValueNotifier<AnalyzeState?>(null);

  /// 剪贴板里像牌桌数据、但不是标准格式时的原因；界面据此弹「不是标准牌桌格式」
  final ValueNotifier<String?> nearMiss = ValueNotifier<String?>(null);

  /// 上一次处理过的剪贴板文本（去重用）
  String? _lastText;
  bool _watching = false;
  AppLifecycleListener? _lifecycle;

  /// 启动时读一次开关，开着就恢复监听
  Future<void> load() async {
    enabled.value = await LocalStore.instance.isClipboardAutoFillEnabled();
    if (enabled.value) await _start();
  }

  /// 同意免责声明后打开 / 关闭，并持久化
  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await LocalStore.instance.setClipboardAutoFillEnabled(value);
    if (value) {
      await _start();
      // 打开就立刻读一次，省得用户还要再复制一遍
      unawaited(checkNow());
    } else {
      await _stop();
      _lastText = null;
    }
  }

  Future<void> _start() async {
    if (_watching) return;
    _watching = true;
    clipboardWatcher.addListener(this);
    // 平台没实现（部分桌面环境没有插件实现）不该把 App 弄崩
    try {
      await clipboardWatcher.start();
    } catch (_) {}
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(checkNow()));
  }

  Future<void> _stop() async {
    if (!_watching) return;
    _watching = false;
    clipboardWatcher.removeListener(this);
    try {
      await clipboardWatcher.stop();
    } catch (_) {}
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  @override
  void onClipboardChanged() => unawaited(checkNow());

  /// 读一次剪贴板并尝试填充。
  ///
  /// [manual] = true 是可视页下拉刷新（备用方案）：无论失败原因是什么都返回
  /// 给调用方去弹 dialog；自动模式只在成功时更新 [state]，失败一律返回 null。
  /// [force] = true 无视开关直接读（后台监听的通知被点开时用）。
  Future<String?> checkNow({bool manual = false, bool force = false}) async {
    if (!manual && !force && !enabled.value) return null;

    final String raw;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      raw = data?.text ?? '';
    } catch (_) {
      return manual ? '读取剪贴板失败：系统拒绝了这次访问' : null;
    }

    if (!manual) {
      if (raw.trim().isEmpty) return null;
      if (raw == _lastText) return null; // 同一份内容不重复处理
    }
    _lastText = raw;

    try {
      state.value = AnalyzeState.parse(raw);
      nearMiss.value = null;
      return null;
    } on AnalyzeParseException catch (e) {
      if (manual) return e.message;
      // 有关键词但格式不对：交给界面提示「不是标准牌桌格式」并给标准模板；
      // 复制的是别的东西（没有这些关键词）就继续静静忽略。
      if (looksLikeBoard(raw)) nearMiss.value = e.message;
      return null;
    }
  }

  /// 无视开关读一次并载入（不弹任何提示）：后台监听的通知被点开时走这条
  Future<void> loadNow() => checkNow(force: true);
}
