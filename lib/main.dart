// M3E Migration 记录：
// - 已迁移：按钮（M3ETextButton/M3EFilledButton.*）、首个下拉菜单（M3EDropdownMenu：
//   配装页右上角动作菜单 + 左侧卡组选择）、界面缩放滑杆（M3ESlider）、
//   引导页语言卡（M3ECard）。
// - 规则 3 未覆盖组件（m3e_core 1.1.0 未提供 → 暂用官方 material 最新组件，
//   待官方 M3E 包覆盖后二次迁移）：AppBar/TabBar/TabBarView、Drawer、ListTile、
//   IconButton、SwitchListTile、RadioGroup/RadioListTile、AlertDialog、SnackBar、
//   CircleAvatar、进度指示器（见 progress_indicator）。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:motor/motor.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:flutter/services.dart' show Clipboard, ClipboardData, MissingPluginException;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'data/card_pool.dart';
import 'data/clipboard_auto_fill.dart';
import 'data/clipboard_watch_service.dart';
import 'data/deck_pool.dart';
import 'data/library_updater.dart';
import 'data/local_store.dart';
import 'data/player_profile.dart';
import 'models/analyze_state.dart';
import 'models/card.dart';
import 'screens/deck_config_screen.dart';
import 'screens/draw_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'theme.dart';
import 'utils/card_import.dart';
import 'utils/log_collector.dart';
import 'widgets/card_face.dart';
import 'widgets/game_card.dart';
import 'utils/log_export.dart';
import 'utils/m3e_toast.dart';

/// 是否已完成新手引导（首次启动时 false，显示引导页）
bool onboardingDone = false;

/// 上次对局未完成时保存的手牌快照（应用被杀后重启时提示恢复）
PendingHand? pendingHand;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogCollector.instance.init();
  // 预加载液态玻璃的 fragment shader。不做的话首次切到玻璃底栏会有一帧白闪，
  // 因为 shader 要等到那一帧才现读磁盘。
  //
  // 关掉包自带的调试性能监视器：它在 debug 下检测到持续掉帧会主动抛 FlutterError，
  // 而模拟器上跑多 pass 玻璃很容易误报，会污染日志、也会被误当成真实异常。
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  await _loadPersistedData();
  onboardingDone = await LocalStore.instance.isOnboardingDone();
  pendingHand = await LocalStore.instance.loadPendingHand();
  LogCollector.instance.log(
    '启动完成：牌库 ${CardPool.instance.cards.length} 张，'
    '卡组 ${DeckPool.instance.savedDecks.length} 个',
  );
  // 用 zone 接管 print 与未捕获异常，扩大日志抓取范围
  runZonedGuarded(
    () => runApp(
      // 玻璃组件的明暗取自 Theme，而本 App 的深色模式允许和系统不一致，
      // 所以把 Material 的 brightness 解析器交给它；不传的话
      // 系统深色 + App 浅色时玻璃的高光和描边会消失。
      LiquidGlassWidgets.wrap(
        child: const MigaApp(),
        brightnessResolver: Theme.maybeBrightnessOf,
      ),
    ),
    (error, stack) {
      LogCollector.instance.log('UNCAUGHT: $error');
      LogCollector.instance.log('STACK: $stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        LogCollector.instance.log(line);
        parent.print(zone, line);
      },
    ),
  );
}

/// 启动时从本地恢复牌库、配装好的牌组与玩家资料
Future<void> _loadPersistedData() async {
  await PlayerProfile.instance.load();
  await themeController.loadUiScale();
  await themeController.loadTheme();
  final library = await LocalStore.instance.loadLibrary();
  if (library != null && library.isNotEmpty) {
    CardPool.instance.setCards(library);
    CardPool.instance.setVersion(
      await LocalStore.instance.loadLibraryVersion(),
    );
  }
  final deckLibrary = {for (final c in CardPool.instance.cards) c.id: c};
  await DeckPool.instance.loadDecks(deckLibrary);
  // 剪贴板自动填充：读开关，开着就恢复监听
  await ClipboardAutoFill.instance.load();
  // 后台监听（Android 前台服务）：开着就重新拉起来
  await ClipboardWatchService.instance.load();
}

final ThemeController themeController = ThemeController();

class MigaApp extends StatelessWidget {
  const MigaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final useMonet = themeController.useMonet;
            final uiScale = themeController.uiScale;
            return MaterialApp(
                title: 'MIGA',
                debugShowCheckedModeBanner: false,
                theme: buildMigaTheme(
                  brightness: Brightness.light,
                  dynamicColorScheme: useMonet ? lightDynamic : null,
                  seedColor: themeController.seedColor,
                  schemeVariant: themeController.schemeVariant,
                  scale: uiScale,
                ),
                darkTheme: buildMigaTheme(
                  brightness: Brightness.dark,
                  dynamicColorScheme: useMonet ? darkDynamic : null,
                  seedColor: themeController.seedColor,
                  schemeVariant: themeController.schemeVariant,
                  scale: uiScale,
                ),
                themeMode: themeController.themeMode,
                // m3e_core 组件读取 material_ui 的 Theme，这里在 Navigator 外层补一份
                // 与当前配色同步的 material_ui 主题（含 m3e 需要的本地化）。
                localizationsDelegates: const [
                  mui.DefaultMaterialLocalizations.delegate,
                ],
                builder: (context, child) => mui.Theme(
                  data: buildM3ETheme(
                    brightness: Theme.of(context).brightness,
                    dynamicColorScheme: useMonet
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? darkDynamic
                              : lightDynamic)
                        : null,
                    seedColor: themeController.seedColor,
                    schemeVariant: themeController.schemeVariant,
                  ),
                  child: child!,
                ),
                home: onboardingDone
                    ? const MainShell()
                    : const OnboardingScreen(),
            );
          },
        );
      },
    );
  }
}

/// 首次启动的新手引导页：第一屏显示 App 名称，其余页面暂为空
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 7;

  final _pageController = PageController();
  int _page = 0;
  String _language = 'zh';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pageCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      await LocalStore.instance.setOnboardingDone();
      if (!mounted) return;
      onboardingDone = true;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  String get _nextLabel {
    if (_page == 3) return '跳过'; // 导入牌库页
    return '下一步';
  }

  /// 下一步 FAB 的图标（导入牌库那一页表示「跳过」）
  IconData get _nextIcon => _page == 3 ? Icons.skip_next : Icons.arrow_forward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: _page >= 5 ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              // 第一屏：App 名称
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MIGA-谜咖',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '点击下一步或向左滑动就可以开始了',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // 语言选择（目前仅提供中文，默认选中）：内容靠左下
              _OnboardingPane(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.language,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '选择语言',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  M3ECard(
                    index: 0,
                    position: M3ECardPosition.single,
                    outerRadius: 12,
                    innerRadius: 4,
                    gap: 0,
                    padding: EdgeInsets.zero,
                    child: RadioGroup<String>(
                      groupValue: _language,
                      onChanged: (v) => setState(() => _language = v ?? 'zh'),
                      child: const RadioListTile<String>(
                        value: 'zh',
                        title: Text('中文'),
                        subtitle: Text('简体中文 🇨🇳'),
                      ),
                    ),
                  ),
                ],
              ),
              // 选择主题：图标 + 莫奈取色开关 + 默认配色方案 + 深色模式（靠左下）
              _OnboardingPane(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.palette_outlined,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '选择主题',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _ThemeSettingsSection(),
                ],
              ),
              // 自动更新牌库（进这一屏就自动拉，失败可重试，也可直接跳过）
              const _AutoLibraryUpdatePage(),
              // 赞助页入口：内容靠左下，按钮落在右下角、FAB 正上方
              _OnboardingPane(
                trailing: M3EFilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SponsorPage()),
                    );
                  },
                  icon: const Icon(Icons.favorite),
                  label: const Text('打开赞助页面'),
                ),
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.favorite,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '赞助',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '如果这个项目对你有帮助，欢迎赞助支持开发者！',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ),
              // 我们的优势：清屏 → 四张卡片缓慢逐张浮现 → 我已了解
              _AdvantagesPage(onContinue: _next),
              // 欢迎使用谜咖（淡入，仅「开始使用」按钮）
              _WelcomePage(onStart: _next),
            ],
          ),
          // 底部导航（优势页/欢迎页完全清屏：隐藏指示器与按钮）
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: _page >= 5
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      M3ETextButton(
                        onPressed: _page > 0
                            ? () => _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              )
                            : null,
                        enabled: _page > 0,
                        child: const Text('上一步'),
                      ),
                      // 页面指示点
                      for (var i = 0; i < _pageCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == _page ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: i == _page
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      const Spacer(),
                      // 下一步：M3E 圆形 FAB。文字放进 tooltip —— 包的扩展 FAB 宽度
                      // 写死 80（_FabDimensions.extendedMinWidth），装不下「下一步」
                      // 三个字，标签会被压没；圆形 FAB + tooltip 才显示得完整。
                      M3EFloatingActionButton(
                        onPressed: _next,
                        tooltip: _nextLabel,
                        child: Icon(_nextIcon),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 生物识别验证。设备无生物识别能力或平台不支持（如桌面端）时直接放行。
Future<bool> authenticateBiometric(String localizedReason) async {
  final auth = LocalAuthentication();
  try {
    final supported = await auth.isDeviceSupported();
    if (!supported) return true; // 设备不支持生物识别，直接放行
    return await auth.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  } on MissingPluginException {
    return true; // 平台无 local_auth 实现（如 Linux 桌面/测试环境），放行
  } catch (_) {
    return false;
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// 底部浮动工具栏是否展开（收起后只留 FAB）
  bool _toolbarExpanded = true;

  static const _titles = ['我们的征途是星辰大海', '配装', '发牌', '可视'];

  /// 每个标签的（未选中图标, 选中图标）
  static const _tabIcons = [
    (Icons.home_outlined, Icons.home_rounded),
    (Icons.construction_outlined, Icons.construction_rounded),
    (Icons.back_hand_outlined, Icons.back_hand_rounded),
    (Icons.analytics_outlined, Icons.analytics_rounded),
  ];

  static const _tabLabels = ['主页', '配装', '发牌', '可视'];

  final _deckConfigKey = GlobalKey<DeckConfigScreenState>();
  final _drawKey = GlobalKey<DrawScreenState>();

  /// 页面平移过渡用；手势滑动被禁用（见 body 里的 physics），只允许代码驱动
  final _pageController = PageController();

  /// 本次会话是否已通过配装页身份验证
  bool _deckAuthPassed = false;

  @override
  void initState() {
    super.initState();
    // 上次对局未完成：首帧后弹窗询问是否恢复
    if (pendingHand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptResumeHand());
    }
    // 首次激活：自动比对一次线上牌库版本（只查一次，之后走右上角菜单）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkLibraryOnFirstLaunch());
    });
    // 剪贴板里像牌桌数据但不是标准格式：提示一次
    ClipboardAutoFill.instance.nearMiss.addListener(_onClipboardNearMiss);
  }

  /// 已经有一个「不是标准牌桌格式」弹窗在显示（避免连续触发堆叠）
  bool _nearMissDialogOpen = false;

  Future<void> _onClipboardNearMiss() async {
    final reason = ClipboardAutoFill.instance.nearMiss.value;
    if (reason == null || _nearMissDialogOpen || !mounted) return;
    _nearMissDialogOpen = true;
    ClipboardAutoFill.instance.nearMiss.value = null;
    await _showNotStandardBoardDialog(context, reason);
    _nearMissDialogOpen = false;
  }

  /// 首次激活的牌库更新：有新版本就换掉并告知用户，没网就下次启动再试
  Future<void> _checkLibraryOnFirstLaunch() async {
    final result = await LibraryUpdater.instance.checkOnFirstLaunch();
    if (!mounted || result.status != LibraryUpdateStatus.updated) return;
    showMigaToast(
      context,
      '牌库已更新到 v${result.version}（${result.count} 张卡牌）',
    );
  }

  /// 手动检查牌库更新（配装页右上角菜单 → 检查牌库更新）
  Future<void> _updateLibrary() async {
    final result = await LibraryUpdater.instance.update();
    if (!mounted) return;
    switch (result.status) {
      case LibraryUpdateStatus.updated:
        showMigaToast(
          context,
          '牌库已更新到 v${result.version}（${result.count} 张卡牌）',
        );
      case LibraryUpdateStatus.upToDate:
        showMigaToast(context, '已是最新版本 v${result.version}');
      case LibraryUpdateStatus.busy:
        showMigaToast(context, '正在更新牌库，请稍候');
      case LibraryUpdateStatus.failed:
        showMigaToast(context, '更新失败：${result.message}');
    }
  }

  /// 点按工具栏标签 / FAB 切页：走与原来 TabBar.onTap 完全相同的校验流程
  Future<void> _selectTab(int i) => _trySelect(i);

  /// 液态玻璃底栏的几何尺寸。必须与 [_buildLiquidToolbar] 传给 GlassTabBar 的值一致，
  /// 因为包内的 preferredSize 就是 `barHeight + verticalPadding * 2`，
  /// 留白算小了页面底部的免责声明/主按钮就会被压住。
  static const double _liquidBarHeight = 64.0;
  static const double _liquidBarVerticalPadding = 20.0;

  /// 底部浮动工具栏占用的高度（含系统手势条），页面内容按它下留白，
  /// 免得页面内的底部元素（主页免责声明、发牌页主按钮等）被工具栏压住
  double _toolbarReserve(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom +
      (themeController.useLiquidGlassBottomBar
          ? _liquidBarHeight + _liquidBarVerticalPadding * 2
          : M3EFloatingToolbarDefaults.containerSize) +
      12;

  /// 底部浮动工具栏：四个标签 + 主操作 FAB
  ///
  /// 外观由设置页的「液态玻璃底栏」开关决定；两种实现共用同一套标签定义
  /// （[_tabIcons] / [_tabLabels] / [_currentIndex]）和同一个 [_selectTab] 回调，
  /// 所以配装页指纹验证、牌组未保存确认这些校验不会被绕过。
  Widget _buildToolbar(BuildContext context) {
    return themeController.useLiquidGlassBottomBar
        ? _buildLiquidToolbar(context)
        : _buildM3EToolbar(context);
  }

  /// M3E 浮动工具栏（默认外观，与历史版本完全一致）
  Widget _buildM3EToolbar(BuildContext context) {
    return M3EFabHorizontalFloatingToolbar(
      expanded: _toolbarExpanded,
      alignment: Alignment.bottomCenter,
      decoration: M3EFloatingToolbarDecoration(
        colors: M3EFloatingToolbarDefaults.vibrantColors(context),
        motion: M3EMotion.expressiveSpatialFast,
      ),
      fabPosition: M3EFloatingToolbarHorizontalFabPosition.end,
      tooltip: '发牌',
      onExpandA11y: () => setState(() => _toolbarExpanded = true),
      onCollapseA11y: () => setState(() => _toolbarExpanded = false),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4.0,
        children: [
          for (var i = 0; i < _titles.length; i++)
            _M3ENavBarTab(
              icon: _tabIcons[i].$1,
              selectedIcon: _tabIcons[i].$2,
              label: _tabLabels[i],
              isSelected: _currentIndex == i,
              onTap: () => unawaited(_selectTab(i)),
            ),
        ],
      ),
      // FAB = App 主操作：去发牌页（发牌页自身的主按钮仍是抽牌）
      floatingActionButton: M3EFloatingActionButton(
        elevation: 0,
        tooltip: '发牌',
        onPressed: () {
          M3EHapticFeedback.light.apply();
          unawaited(_selectTab(2));
        },
        child: const Icon(Icons.back_hand_rounded),
      ),
    );
  }

  /// 液态玻璃底栏：同样四个标签 + 右侧主操作按钮。
  ///
  /// 用 liquid_glass_widgets 的 [GlassTabBar.bottom]（iOS 26 的 UITabBar 形态）：
  /// 它自带玻璃药丸、果冻指示器与标签渲染，所以这里没法直接塞 [_M3ENavBarTab]，
  /// 改为把同一组 [_tabIcons] / [_tabLabels] 映射成 [GlassTab]。
  /// 点击回调仍走 [_selectTab]，与 M3E 版行为一致。
  ///
  /// ## 外观一律用包自带的默认值
  ///
  /// 材质与取色全部交给 liquid_glass_widgets 的默认值（中性玻璃 + 包内 Cupertino
  /// label 取色），即刚接入液态玻璃时的观感：不传 `settings`，也不传
  /// `indicatorColor` / 各种前景色，因此底栏不跟随全局 Monet/ColorScheme。
  /// 曾经把这些旋钮逐个接到 `Theme.of(context).colorScheme` 上，观感不好，已回退，
  /// 不要再接回来。
  Widget _buildLiquidToolbar(BuildContext context) {
    final bar = GlassTabBar.bottom(
      tabs: [
        for (var i = 0; i < _titles.length; i++)
          GlassTab(
            icon: Icon(_tabIcons[i].$1),
            activeIcon: Icon(_tabIcons[i].$2),
            label: _tabLabels[i],
          ),
      ],
      selectedIndex: _currentIndex,
      onTabSelected: (i) => unawaited(_selectTab(i)),
      barHeight: _liquidBarHeight,
      verticalPadding: _liquidBarVerticalPadding,
      // 位置与 M3E 版的 fabPosition: end 对齐，动作也同样是去发牌页
      // （size 与 spacing 显式写成包内默认值，让描边的几何常量有确定的来源）
      spacing: _liquidBarTabSpacing,
      extraButton: GlassTabBarExtraButton(
        size: _liquidExtraButtonSize,
        icon: const Icon(Icons.back_hand_rounded),
        label: '发牌',
        onTap: () {
          M3EHapticFeedback.light.apply();
          unawaited(_selectTab(2));
        },
      ),
    );

    // 描边只在浅色模式叠加；深色模式与改动前完全一致（不多套任何一层）
    final isLight =
        (Theme.maybeBrightnessOf(context) ?? Brightness.light) ==
            Brightness.light;
    if (!isLight) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: bar,
      );
    }

    return Align(
      // GlassTabBar 本身不带 Align/Positioned，父级是铺满屏的 Stack，不包一层会顶到左上角
      alignment: Alignment.bottomCenter,
      child: Stack(
        children: [
          bar,
          // 描的是那条不动的玻璃胶囊本身，见 [_liquidBarOutline]
          Positioned.fill(child: _liquidBarOutline(context)),
        ],
      ),
    );
  }

  // ── 液态玻璃底栏「玻璃胶囊」描边（仅浅色模式）──────────────────────────────
  //
  // 包（liquid_glass_widgets 1.6.2）没给玻璃留描边口子：`GlassTabBar.bottom`
  // 只有 indicatorColor / indicatorSettings / indicatorBorderRadius /
  // indicatorExpansion，`LiquidGlassSettings` 全字段里也没有 border/stroke/outline。
  // 所以不 fork 包，改在 App 侧按包内布局叠一圈静止的圆角描边（IgnorePointer）。
  //
  // 曾经描的是「跟着选中项走的指示器药丸」，但那颗药丸是弹簧驱动、还带果冻外扩
  // 与拖动 sway，而 `_currentIndex` 只在松手时才变，过渡帧里描边必然错位/滞后。
  // 现在描的是底栏那条**不动的**玻璃胶囊，所以任何时候都严丝合缝。

  /// 包内 `horizontalPadding` / `verticalPadding` 的默认值，本页只显式传了后者
  static const double _liquidBarHorizontalPadding = 20.0;

  /// 右侧「发牌」按钮尺寸（`GlassTabBarExtraButton.size` 的包内默认值）
  static const double _liquidExtraButtonSize = 64.0;

  /// `GlassTabBar.bottom` 的 spacing 默认值，也是玻璃胶囊与 extraButton 的间隔
  static const double _liquidBarTabSpacing = 8.0;

  /// 叠在底栏上层的一圈玻璃胶囊描边，颜色取当前主题 `colorScheme.outline`
  /// （Monet/种子色换了描边跟着走，不写死色值），线宽 1.2 逻辑像素。
  ///
  /// 用**不透明**的 `outline`：描边是压在这条玻璃的亮边缘上的，加 alpha 会被
  /// 底下那圈近白的玻璃高光冲淡 —— 实测 alpha 0.8 渲染成 #959199（L=0.2864），
  /// 对相邻玻璃 #FDFAFD（L=0.9635）只有 2.99:1，刚好掉在 3:1 门槛下面；
  /// 不透明时渲染成 #7A757F（L=0.1839，即本主题 outline 原色）对同一玻璃
  /// 是 4.33:1，且线色不再受底下玻璃影响。
  ///
  /// 玻璃胶囊在底栏 box 里的位置全是常量内缩，不需要量宽度：
  /// 左 = `horizontalPadding`；上/下 = `verticalPadding`（底栏 box 高正是
  /// `barHeight + verticalPadding * 2`，见包内 preferredSize）；右 =
  /// `horizontalPadding + extraButton.size + spacing`（标签区从 `horizontalPadding`
  /// 起、宽 `barWidth - 2*horizontalPadding - (size + spacing)`，所以右侧总内缩正是
  /// 这三者之和）；高度正好是 `barHeight`。
  ///
  /// 依据 `tab_bar_bottom_layout.dart`：`AdaptiveLiquidGlassLayer` 里一层
  /// `Padding(horizontal: 20, vertical: 20)`，其内 `SizedBox(height: barHeight)`
  /// 的 Stack 中 `Positioned(left: 0, top: 0, width: tabPillW, height: barHeight)`
  /// 就是那块玻璃胶囊（`resolveTabPillWidth` 在 tabWidth 为 null 时返回可用宽度），
  /// extraButton 靠右占 `size + spacing`。
  ///
  /// 实测（emulator-5554，1080x2400@2.625）：四条边的描边线心在
  /// 53.5/2117.5/836.5/2282.5 px，由本函数算出的胶囊路径是
  /// 52.5/2118/838.9/2286 px，误差 ≤3px（≈1 逻辑像素，玻璃 SDF 边缘本身还有
  /// 约 1px 软过渡），即描边严丝合缝地压在玻璃边缘上。曾经漏加右侧的
  /// `horizontalPadding`，描边右端会多伸进发牌按钮 20 逻辑像素，别再漏。
  ///
  /// 误差风险：只有包内 horizontalPadding / verticalPadding / extraButton 默认
  /// 尺寸变了，或胶囊外又包了一层 padding，才需要同步这些常量；
  /// `_liquidBarHeight` / `_liquidBarVerticalPadding` 是本页显式传给包的值，不在此列。
  Widget _liquidBarOutline(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _liquidBarHorizontalPadding,
          _liquidBarVerticalPadding,
          _liquidBarHorizontalPadding +
              _liquidExtraButtonSize +
              _liquidBarTabSpacing,
          _liquidBarVerticalPadding,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // 半径取半高即胶囊，与包内 barBorderRadius 的默认值
            // `GlassDefaults.capsuleRadius` 观感一致
            borderRadius: BorderRadius.circular(_liquidBarHeight / 2),
            border: Border.all(color: outline, width: 1.2),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 尝试切换页面；被取消（未通过验证/未保存提示取消）时返回 false
  Future<bool> _trySelect(int index) async {
    if (index == _currentIndex) return true;
    if (index == 1 && !_deckAuthPassed) {
      final enabled = await LocalStore.instance.isDeckAuthEnabled();
      if (enabled) {
        final ok = await authenticateBiometric('打开配装页面前请先验证身份');
        if (!ok || !mounted) return false;
      }
      _deckAuthPassed = true;
    }
    if (!mounted) return false;
    final deckState = _deckConfigKey.currentState;
    final hasUnsaved =
        _currentIndex == 1 && deckState != null && deckState.hasUnsavedChanges;
    if (hasUnsaved) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('未保存的更改'),
          content: const Text('牌组有未保存的修改，是否保存？'),
          actions: [
            M3ETextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('取消'),
            ),
            M3ETextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('放弃'),
            ),
            M3EFilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (action == null || action == 'cancel') return false;
      if (action == 'save') {
        if (!deckState.isValidDeckSize) {
          if (mounted) {
            await deckState.showInvalidDeckSizeDialog(context);
          }
          return false;
        }
        await deckState.saveChanges();
      } else if (action == 'discard') {
        deckState.revertChanges();
      }
    }
    setState(() => _currentIndex = index);
    // 页面用 PageView 平移过渡（和原来 TabBarView 的手感一致）
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
        ),
      );
    }
    LogCollector.instance.log('切换页面：${_titles[index]}');
    return true;
  }

  /// 上次对局未完成：应用被杀后重启时询问是否重新载入手牌
  Future<void> _promptResumeHand() async {
    final saved = pendingHand;
    if (saved == null || !mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复上次对局'),
        content: Text(
          '检测到上次有 ${saved.handIds.length} 张手牌未使用，'
          '是否重新载入继续对局？',
        ),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('放弃'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新载入'),
          ),
        ],
      ),
    );
    pendingHand = null;
    if (!mounted) return;
    if (resume == true) {
      final ok = await _trySelect(2);
      if (!ok || !mounted) return;
      // PageView 里第 2 页是在滑动过程中才构建的：必须等动画走完再读它的状态，
      // 否则 currentState 还是 null，会静默把待恢复的手牌清掉
      if (_pageController.hasClients) {
        await _pageController.animateToPage(
          2,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
        );
        if (!mounted) return;
      }
      final drawState = _drawKey.currentState;
      if (drawState == null || !drawState.restorePendingHand(saved)) {
        unawaited(LocalStore.instance.clearPendingHand());
      }
    } else {
      await LocalStore.instance.clearPendingHand();
    }
  }

  /// 一键清空牌库（含配装好的牌组），需二次确认。
  Future<void> _clearCardLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空牌库'),
        content: const Text('确定要清空牌库吗？配装好的牌组也会一并清空，此操作不可撤销。'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    CardPool.instance.reset();
    DeckPool.instance.clear();
    await LocalStore.instance.saveLibrary(const []);
    await LocalStore.instance.saveDeck(const []);
    // 让配装页的选配同步清空
    _deckConfigKey.currentState?.revertChanges();
    if (mounted) {
      showMigaToast(context, '牌库已清空');
    }
  }

  /// 配装页右上角菜单的菜单项（牌库操作 + 卡组操作）
  static const List<M3EDropdownItem<String>> _deckMenuItems = [
    M3EDropdownItem(label: '牌库操作', value: 'hdr_lib', disabled: true),
    M3EDropdownItem(label: '检查牌库更新', value: 'update_library'),
    M3EDropdownItem(label: '导入卡牌JSON', value: 'import_library'),
    M3EDropdownItem(label: '一键清空牌库', value: 'clear_library'),
    M3EDropdownItem(label: '卡组操作', value: 'hdr_deck', disabled: true),
    M3EDropdownItem(label: '导入牌组', value: 'import_deck'),
    M3EDropdownItem(label: '导出牌组', value: 'export_deck'),
    M3EDropdownItem(label: '新建卡组', value: 'new_deck'),
    M3EDropdownItem(label: '重命名卡组', value: 'rename_deck'),
    M3EDropdownItem(label: '删除卡组', value: 'delete_deck'),
  ];

  static IconData _deckMenuIcon(String value) => switch (value) {
    'update_library' => Icons.cloud_sync_outlined,
    'import_library' => Icons.file_download_outlined,
    'clear_library' => Icons.delete_sweep_outlined,
    'import_deck' => Icons.qr_code_scanner,
    'export_deck' => Icons.qr_code_2,
    'new_deck' => Icons.add,
    'rename_deck' => Icons.drive_file_rename_outline,
    'delete_deck' => Icons.delete_outline,
    _ => Icons.more_horiz,
  };

  /// 执行配装页右上角菜单动作
  void _handleDeckAction(String value) {
    switch (value) {
      case 'update_library':
        unawaited(_updateLibrary());
      case 'import_library':
        importCardLibrary(context);
      case 'clear_library':
        _clearCardLibrary();
      case 'import_deck':
        _deckConfigKey.currentState?.importDeck();
      case 'export_deck':
        _deckConfigKey.currentState?.exportDeck();
      case 'new_deck':
        _deckConfigKey.currentState?.addDeck();
      case 'rename_deck':
        _deckConfigKey.currentState?.renameActiveDeck();
      case 'delete_deck':
        _deckConfigKey.currentState?.deleteActiveDeck();
    }
  }

  /// 牌库/卡组操作菜单（M3E 底部弹层）：分组标题 + 可点条目
  Future<void> _showDeckMenu() async {
    final value = await showM3EModalBottomSheet<String>(
      context: context,
      builder: (context) => M3EBottomSheet(
        title: const Text('牌库与卡组相关操作'),
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _deckMenuItems)
                if (item.disabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  Material(
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(item.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(_deckMenuIcon(item.value), size: 20),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                item.label,
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    if (value != null) _handleDeckAction(value);
  }

  @override
  Widget build(BuildContext context) {
    // 页面保活由各页 AutomaticKeepAliveClientMixin 负责，TabBarView 驱动切换
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          // 发牌页帮助按钮（仅发牌 Tab 显示）
          if (_currentIndex == 2)
            IconButton(
              tooltip: '帮助',
              onPressed: _drawKey.currentState?.showDrawHelp,
              icon: const Icon(Icons.help_outline),
            ),
          // 配装页右上角菜单：牌库操作 + 卡组操作（M3E 底部弹层）
          // 原来用 M3EDropdownMenu，但它的面板宽度写死等于触发器宽度
          // （m3e_dropdown_menu.dart:800 `width: renderBoxSize.width`），
          // 触发器一窄菜单就跟着窄，所以改成小图标 + 弹层
          if (_currentIndex == 1)
            IconButton(
              tooltip: '牌库与卡组操作',
              onPressed: () => unawaited(_showDeckMenu()),
              icon: const Icon(Icons.more_vert, size: 20),
            ),
        ],
      ),
      // 切页由底部浮动工具栏驱动（原 TabBar / TabBarView 已移除）。
      // 四个页面各带 keepAlive，切走的页保留状态，TickerMode 冻结隐藏页动画。
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: _toolbarReserve(context)),
              // 平移过渡用 PageView；禁用用户手势滑动 ——
              // 滑动切换会绕过 _trySelect 里的配装页指纹验证与牌组未保存确认
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < _titles.length; i++)
                    TickerMode(enabled: i == _currentIndex, child: _pages[i]),
                ],
              ),
            ),
          ),
          // 工具栏自带 Align，需要铺满的父级才能按 alignment 定位；
          // 再按系统手势条高度上移，避免压住底部那条小白条
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: _buildToolbar(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 关闭抽屉等动画结束后再进新页面，避免两个动画叠加掉帧
  void _openAfterDrawerClose(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      }
    });
  }

  /// 四个主页面（常驻构建，配合 TickerMode 冻结隐藏页动画，切换零成本）
  List<Widget> get _pages => <Widget>[
        const HomePage(),
        DeckConfigScreen(key: _deckConfigKey),
        DrawScreen(key: _drawKey, embedded: true),
        const _AnalyzePage(),
      ];

  /// 侧边抽屉：收纳个人页与设置页
  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: RepaintBoundary(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ListenableBuilder(
                    listenable: PlayerProfile.instance,
                    builder: (context, _) {
                      final profile = PlayerProfile.instance;
                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            backgroundImage: profile.avatarPath != null
                                ? FileImage(File(profile.avatarPath!))
                                : null,
                            child: profile.avatarPath == null
                                ? Icon(
                                    Icons.person,
                                    size: 26,
                                    color: theme.colorScheme.primaryContainer,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              profile.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('个人'),
              onTap: () => _openAfterDrawerClose(
                context,
                const ProfileEditScreen(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () => _openAfterDrawerClose(context, const SettingsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('赞助'),
              onTap: () => _openAfterDrawerClose(context, const SponsorPage()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部浮动工具栏里的一个标签：选中时宽度从 48 弹性展开到 110 并淡入文字。
///
/// 结构与 m3e_core 示例的浮动工具栏用法一致（弹簧用 [SingleMotionController]）。
class _M3ENavBarTab extends StatefulWidget {
  const _M3ENavBarTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_M3ENavBarTab> createState() => _M3ENavBarTabState();
}

class _M3ENavBarTabState extends State<_M3ENavBarTab>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SingleMotionController(
      motion: M3EMotion.expressiveSpatialFast.toMotion(),
      vsync: this,
      initialValue: widget.isSelected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant _M3ENavBarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      _controller.animateTo(widget.isSelected ? 1.0 : 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value.clamp(0.0, 1.0);
        final width = 48.0 + (110.0 - 48.0) * progress;

        final contentColor = widget.isSelected
            ? cs.onSurface
            : cs.onPrimaryContainer;

        return Container(
          width: width,
          height: 48.0,
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: BoxDecoration(
            color: widget.isSelected ? cs.surfaceContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(24.0),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24.0),
              onTap: () {
                M3EHapticFeedback.light.apply();
                widget.onTap();
              },
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return contentColor.withValues(alpha: 0.1);
                }
                if (states.contains(WidgetState.hovered)) {
                  return contentColor.withValues(alpha: 0.08);
                }
                return null;
              }),
              child: ClipRect(
                child: Center(
                  child: OverflowBox(
                    minWidth: 0,
                    maxWidth: 140,
                    minHeight: 0,
                    maxHeight: 48,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isSelected ? widget.selectedIcon : widget.icon,
                          color: contentColor,
                          size: 24.0,
                        ),
                        if (progress > 0.01)
                          ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Opacity(
                                opacity: progress,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6.0),
                                  child: Text(
                                    widget.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: contentColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _homeUrl = 'https://pd.qq.com/s/8p3kuzao3?b=9';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 大标题上移
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MIGA-谜咖',
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Make Inscryption Great Again!',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // 中部 WebView，底部留出发牌按钮的位置
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const _HomeWebView(url: _homeUrl),
                    ),
                  ),
                ),
              ],
            ),
            // FAB 左侧空白处的免责声明
            Positioned(
              left: 16,
              right: 168,
              bottom: 24,
              child: Text(
                '上方页面所展示内容均来自社区官方腾讯频道，软件开发者不对其内容做保证',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可视页：上方三数值（骨头/能量/玛珂）+ 手牌数 + 横向滑动卡牌，
/// 下方为对称布局，上下卡牌同步滚动。
///
/// 下半（资源行贴屏幕下沿那一半）是手机持有者自己的数据，套一张大卡片背景
/// 当作「己方」标记；上半什么都不套，两块一眼能分开。
class _AnalyzePage extends StatefulWidget {
  const _AnalyzePage();

  @override
  State<_AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<_AnalyzePage>
    with AutomaticKeepAliveClientMixin {
  static const _cardW = 120.0;
  static const _cardH = 168.0;

  /// 卡牌行两侧渐变模糊的宽度（8 层 × 每层 3）
  static const _edgeBlurWidth = 24.0;

  final _topScroll = ScrollController();
  final _bottomScroll = ScrollController();
  final _pullController = M3EPullToRefreshController();
  bool _syncing = false;

  /// 最近一次读到并解析成功的对局数据；null = 还没加载过。
  /// 数据源统一是 [ClipboardAutoFill]：自动监听和下拉刷新都写到它那儿。
  AnalyzeState? get _game => ClipboardAutoFill.instance.state.value;

  /// 左右两侧现在有没有被视口裁掉的卡（决定那一侧要不要显示渐变模糊）。
  /// 停在最左/最右时对应那一侧不该糊，否则第一张牌会被白白抹掉一条边。
  bool _edgeLeft = false;
  bool _edgeRight = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 上下卡牌滚动同步
    _topScroll.addListener(() => _sync(_topScroll, _bottomScroll));
    _bottomScroll.addListener(() => _sync(_bottomScroll, _topScroll));
    // 两侧渐变模糊的显隐（滚动到最左/最右时要收起）
    _topScroll.addListener(() => _updateEdgeMask(_topScroll));
    _bottomScroll.addListener(() => _updateEdgeMask(_bottomScroll));
    // 首帧还没滚动过，监听器不会触发，补算一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateEdgeMask(_bottomScroll);
    });
    // 剪贴板自动填充：解析出新数据就重建整页
    ClipboardAutoFill.instance.state.addListener(_onAutoFill);
  }

  void _updateEdgeMask(ScrollController controller) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final left = controller.offset > 1;
    final right = controller.offset < position.maxScrollExtent - 1;
    if (left == _edgeLeft && right == _edgeRight) return;
    setState(() {
      _edgeLeft = left;
      _edgeRight = right;
    });
  }

  void _onAutoFill() {
    if (mounted) setState(() {});
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset);
    _syncing = false;
  }

  /// 下拉刷新（备用方案）：不联网，只读一次剪贴板。读到合法格式就整页换成
  /// 这份数据，格式不对（必填项为空、数值超范围等）就弹 dialog 指出哪一行不对。
  Future<void> _refreshFromClipboard() async {
    // manual：失败原因原样返回，交给下面的 dialog 显示
    final failure = await ClipboardAutoFill.instance.checkNow(manual: true);

    // 解析本身是瞬时的，停一下让加载动画走一轮，否则指示器只是一闪。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    if (failure == null) return;
    // 不 await：dialog 是模态的，await 会让刷新头一直转着等用户点掉它。
    unawaited(_showLoadFailed(failure));
  }

  Future<void> _showLoadFailed(String reason) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('加载失败'),
      content: Text(reason),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _topScroll.dispose();
    _bottomScroll.dispose();
    _pullController.dispose();
    ClipboardAutoFill.instance.state.removeListener(_onAutoFill);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return M3EPullToRefreshIndicator(
      controller: _pullController,
      shapes: const [Shapes.softBurst, Shapes.sunny, Shapes.pill],
      triggerDistance: 110.00,
      indicatorHeight: 64.00,
      dragResistance: 0.50,
      maxDragMultiplier: 2.00,
      edgeOffset: 0.00,
      springMotion: M3EMotion.expressiveSpatialDefault,
      hapticFeedback: M3EHapticFeedback.medium,
      onRefresh: _refreshFromClipboard,
      style: M3EPullToRefreshStyle(
        size: 56.00,
        padding: const EdgeInsets.all(8.00),
        elevation: 4.00,
        borderRadius: BorderRadius.circular(28.00),
        triggerDistance: 110.00,
        indicatorHeight: 64.00,
        springMotion: const M3EMotion.custom(
          stiffness: 380.00,
          damping: 0.80,
        ),
        hapticFeedback: M3EHapticFeedback.medium,
        dragResistance: 0.50,
        maxDragMultiplier: 2.00,
      ),
      // 内容不满一屏时也要能下拉，所以固定用 AlwaysScrollableScrollPhysics
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              // 原来上下两块之间夹着天平，去掉后改由 mainAxisAlignment 均分
              // 剩余高度，两块内容不会贴在一起、也不会留下空档。
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 上半：数值 → 手牌数 → 卡牌（对面那一半，不加背景）
                _halfSection(
                  theme,
                  _game?.enemy,
                  flipped: false,
                  own: false,
                  controller: _topScroll,
                ),
                // 两半中间（原来天平的位置）：进度取自剪贴板的「天平」，
                // 还没加载过就停在默认的 50%。颜色不传，用主题默认的 primary。
                M3ELinearWavyProgressIndicator(
                  value: _game?.balance ?? 0.50,
                  width: 320.00,
                  height: 20.00,
                  strokeWidth: 4.00,
                  trackStrokeWidth: 4.00,
                  gapSize: 4.00,
                  stopSize: 4.00,
                  wavelength: 20.00,
                  waveSpeed: 20.00,
                ),
                // 下半：对称倒序（不再有天平，直接跟在上面一块之后）。
                // 手机持有者看的是这一半（资源行贴屏幕下沿），所以标成己方。
                _halfSection(
                  theme,
                  _game?.own,
                  flipped: true,
                  own: true,
                  controller: _bottomScroll,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 一侧的内容：资源行 + 手牌数 + 四个卡位。
  /// [side] 为 null 表示还没从剪贴板加载过：数值显示占位符、卡位全空。
  Widget _halfSection(
    ThemeData theme,
    AnalyzeSide? side, {
    required bool flipped,
    required bool own,
    required ScrollController controller,
  }) {
    const noValue = '—';
    final resources = Row(
      children: [
        // 三格：骨头 / 能量 / 玛珂（靠图标区分，格内只放图标 + 数值）
        for (final (icon, value) in [
          (Icons.blur_on, side == null ? noValue : '${side.bones}'),
          (Icons.bolt, side == null ? noValue : '${side.energy}'),
          // 剪贴板格式里没有「玛珂」这一项，所以这格没有数据来源。
          (Icons.auto_awesome, noValue),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _resourceTile(theme, icon, value, own: own),
            ),
          ),
      ],
    );
    final countText = Text(
      '手牌数 ${side == null ? noValue : '${side.handCount}'}',
      style: theme.textTheme.titleMedium,
    );
    final slots = side?.slots ?? const <AnalyzeCard?>[];
    final cards = SizedBox(
      height: _cardH,
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: _cardW,
                  height: _cardH,
                  child: i < slots.length && slots[i] != null
                      ? _miniCard(theme, slots[i]!)
                      : _emptyCard(theme),
                ),
              ),
            ),
          ),
          // 两侧：被视口裁断的卡边做一层渐变模糊，不然看着像被硬切了一刀。
          // 滚到最左/最右时那一侧没有裁断的卡，用 AnimatedOpacity 收起来
          // （opacity 0 时子树不参与绘制，BackdropFilter 也就没开销）。
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edgeBlurWidth,
            child: AnimatedOpacity(
              opacity: _edgeLeft ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: _edgeBlur(left: true),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _edgeBlurWidth,
            child: AnimatedOpacity(
              opacity: _edgeRight ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: _edgeBlur(left: false),
            ),
          ),
        ],
      ),
    );

    final section = Column(
      children: flipped
          ? [
              cards,
              const SizedBox(height: 8),
              countText,
              const SizedBox(height: 8),
              resources,
            ]
          : [
              resources,
              const SizedBox(height: 8),
              countText,
              const SizedBox(height: 8),
              cards,
            ],
    );

    // 两侧内边距取同一组数值：对面那半虽然没有背景，也套同样的内边距，
    // 否则它会是整幅宽度、里面的组件比己方那一侧大一圈。
    const sectionInset = EdgeInsets.fromLTRB(8, 12, 8, 12);
    // 己方背景那层 1px 描边（BoxDecoration 的 border.dimensions）同样会把
    // 内容顶进去 1px，所以从 padding 里减掉，两侧内容盒才逐像素相等。
    const sectionBorderWidth = 1.0;

    if (!own) return Padding(padding: sectionInset, child: section);

    // 己方一侧的整块背景：M3E 分段表面（与设置页同一套语言），
    // elevation 默认 0 且这里不传 elevation，所以只有圆角 + 一层低透明度
    // primaryContainer 底 + 一条细描边，没有投影 —— 不会重演「阴影太重」。
    final cs = theme.colorScheme;
    return M3ESegmentedColumn(
      outerRadius: 24,
      // 见上面的 sectionInset：减掉描边宽度后，里面的内容盒与对面完全等宽
      padding: sectionInset.subtract(const EdgeInsets.all(sectionBorderWidth)),
      color: cs.primaryContainer.withValues(alpha: 0.40),
      border: BorderSide(
        width: sectionBorderWidth,
        color: cs.primary.withValues(alpha: 0.35),
      ),
      children: [section],
    );
  }

  /// 卡牌行一侧的渐变模糊。
  ///
  /// 关键是采样要密：每层只有 3 逻辑像素宽，由外向内叠 8 层，单层 sigma 按
  /// "平方和恰好线性增长"取值，于是**累计**模糊强度从最内侧的 ≈0.75 均匀爬到
  /// 最外侧的 ≈6。层数少（之前 3 层、sigma 直接跳 3→5→7）时，模糊强度是
  /// 台阶状跳变的，边上能看出硬缝 —— 那就是"采样率太低"的来源。
  /// 8 层每层只有 3px 宽，总模糊面积比原来还小，开销反而更低。
  Widget _edgeBlur({required bool left}) {
    const step = 3.0;
    // 累计 sigma 目标：0.75 / 1.5 / 2.25 / … / 6.0（线性），反推每层增量
    const sigmas = <double>[0.75, 1.30, 1.68, 1.98, 2.25, 2.49, 2.70, 2.90];
    return IgnorePointer(
      child: Stack(
        children: [
          for (var i = 0; i < sigmas.length; i++)
            Positioned(
              left: left ? 0 : null,
              right: left ? null : 0,
              top: 0,
              bottom: 0,
              // 最宽的一层 sigma 最小、先画；越靠边越窄越糊，叠在上面
              width: step * (sigmas.length - i),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: sigmas[i],
                    sigmaY: sigmas[i],
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 三数值（骨头/能量/玛珂）的单格：用 M3E 的 M3ESegmentedRow /
  /// M3ESegmentedItem 承载，跟本 App 其它地方（设置页、配装页）同一种
  /// expressive 分段表面语言，不再自己写 Container + BoxShadow。
  ///
  /// 两格（图标 / 数值）各自居中。
  ///
  /// [own] 为 true 时换成最浅的 surface 打底 + 一条细描边：己方那三格坐在
  /// primaryContainer 的大底上，默认的 surfaceContainer 跟底色几乎同色
  /// （都偏粉），糊在一起看不清。
  Widget _resourceTile(
    ThemeData theme,
    IconData icon,
    String value, {
    required bool own,
  }) {
    final cs = theme.colorScheme;
    return M3ESegmentedRow(
      outerRadius: 12,
      innerRadius: 4,
      gap: 2,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: own ? cs.surfaceContainerLowest : null,
      border: own ? BorderSide(color: cs.outlineVariant) : null,
      // 两格各自把自己的内容居中：分段行只负责分格（每格宽度是撑满的，
      // 所以行上的 mainAxisAlignment 管不到格内），格内得自己 Center。
      children: [
        Center(child: Icon(icon, size: 16, color: cs.primary)),
        Center(
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// 一个上场卡位：攻击/血量用剪贴板里的当场数值（可能被 buff 过），
  /// 名字能在牌库里找到时，能力、费用这些静态信息照搬牌库 ——
  /// 这样卡面是完整的，而不是只有一个名字和 0 费用。
  Widget _miniCard(ThemeData theme, AnalyzeCard slot) {
    final lib = CardPool.instance.findByName(slot.name);
    final card = CardData(
      id: lib?.id ?? slot.name,
      name: slot.name,
      cost: lib?.cost ?? 0,
      costText: lib?.costText,
      attack: slot.attack,
      health: slot.health,
      skills: lib?.skills ?? const [],
    );
    // 只保留圆角裁切，卡牌不再投影（阴影太重）。
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const GameCard(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
          ),
          Positioned.fill(
            child: CardFace(
              card: card,
              width: _cardW,
              height: _cardH,
              reveal: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );
  }
}

/// 默认配色可选的种子颜色
const _seedColors = [
  Colors.deepPurple,
  Colors.indigo,
  Colors.blue,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.lime,
  Colors.orange,
  Colors.deepOrange,
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.brown,
  Colors.blueGrey,
  Colors.grey,
];

/// 色彩风格（DynamicSchemeVariant）与中文名
const _schemeVariants = <DynamicSchemeVariant, String>{
  DynamicSchemeVariant.tonalSpot: '色调焦点',
  DynamicSchemeVariant.fidelity: '保真',
  DynamicSchemeVariant.monochrome: '单色',
  DynamicSchemeVariant.neutral: '中性',
  DynamicSchemeVariant.vibrant: '鲜艳',
  DynamicSchemeVariant.expressive: '表现',
  DynamicSchemeVariant.content: '内容',
  DynamicSchemeVariant.rainbow: '彩虹',
  DynamicSchemeVariant.fruitSalad: '果色',
};

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checkColor = color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.onSurface : cs.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected ? Icon(Icons.check, color: checkColor, size: 20) : null,
      ),
    );
  }
}

/// 设置页分类小标题
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 液态玻璃底栏开关：关 → 开时先二次确认，确认后连深色模式一起打开。
///
/// 液态玻璃底栏在浅色模式下的选中指示器对比度只有约 1.25:1，可读性不达标，
/// 所以"开玻璃"的前提是"用深色"；取消则什么都不变（不改主题、不改玻璃）。
Future<void> _toggleLiquidBottomBar(BuildContext context) async {
  if (themeController.useLiquidGlassBottomBar) {
    themeController.setBottomBarStyle(kBottomBarStyleM3E);
    return;
  }
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开启液态玻璃底栏'),
      content: const Text(
        '液态玻璃底栏在浅色模式下对比度不足，文字与图标可读性较差。'
        '开启后会同时切换到深色模式，以保证底栏的可读性。',
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意'),
        ),
      ],
    ),
  );
  if (agreed != true) return;
  // 两个 setter 各自持久化：这里只保证"玻璃开 ⇒ 深色"成立，顺序不影响最终落地状态
  themeController.setThemeMode(ThemeMode.dark);
  themeController.setBottomBarStyle(kBottomBarStyleLiquid);
}

/// 剪贴板自动填充开关：关 → 开时先弹免责声明，同意才打开（并立刻读一次剪贴板）。
/// 关闭不需要声明，直接停掉监听。
Future<void> _toggleClipboardAutoFill(BuildContext context) async {
  final auto = ClipboardAutoFill.instance;
  if (auto.enabled.value) {
    await auto.setEnabled(false);
    if (context.mounted) showMigaToast(context, '已关闭自动读取剪贴板');
    return;
  }
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开启自动读取剪贴板'),
      content: const Text(
        '开启后 MIGA 会读取剪贴板内容，仅用于自动填充牌桌数据'
        '（骨头 / 能量 / 手牌数 / 上场卡牌 / 天平）。'
        '\n\n'
        'MIGA 不会收集、上传或分享任何信息：剪贴板内容只在本机解析，'
        '解析结果也只保存在本机。'
        '\n\n'
        '受系统限制，Android 10 及以上只有 MIGA 在前台时才能读到剪贴板；'
        '在游戏里复制后切回 MIGA 会自动补读一次。',
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意'),
        ),
      ],
    ),
  );
  if (agreed != true) return;
  await auto.setEnabled(true);
  if (context.mounted) showMigaToast(context, '已开启自动读取剪贴板');
}

/// 「剪贴板里像牌桌数据、但不是标准格式」提示：给原因 + 标准模板，可一键复制。
Future<void> _showNotStandardBoardDialog(
  BuildContext context,
  String reason,
) async {
  final copied = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('不是标准牌桌格式'),
      content: SingleChildScrollView(
        child: Text(
          '剪贴板里检测到骨头 / 能量 / 手牌 / 天平，但格式不符合标准牌桌：'
          '\n\n$reason'
          '\n\n标准格式是：\n$kBoardTemplate',
          style: const TextStyle(height: 1.45),
        ),
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('知道了'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('复制标准牌桌'),
        ),
      ],
    ),
  );
  if (copied != true || !context.mounted) return;
  await Clipboard.setData(const ClipboardData(text: kBoardTemplate));
  if (context.mounted) {
    showMigaToast(context, '已复制标准牌桌格式，填好数值再复制一次即可');
  }
}

/// 后台监听剪贴板开关（Android 前台服务）。
///
/// 开启前必须说清两件事：会常驻一条通知保活；Android 10+ 默认禁止后台读剪贴板，
/// 需要先执行一次 `adb shell appops set com.miga.android READ_CLIPBOARD allow`。
Future<void> _toggleClipboardWatch(BuildContext context) async {
  final service = ClipboardWatchService.instance;
  if (!service.isSupported) {
    showMigaToast(context, '后台监听只支持 Android');
    return;
  }
  if (service.enabled.value) {
    await service.setEnabled(false);
    if (context.mounted) showMigaToast(context, '已关闭后台监听剪贴板');
    return;
  }
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开启后台监听剪贴板'),
      content: const Text(
        '开启后会常驻一条通知来保活。检测到剪贴板里是牌桌数据时，'
        '会再弹一条横幅通知，点它即可回到 MIGA 并自动载入。'
        '\n\n'
        '注意：Android 10 起系统默认禁止后台读取剪贴板，需要先用电脑（或用 '
        'Shizuku）执行一次：'
        '\n\n'
        'adb shell appops set com.miga.android READ_CLIPBOARD allow'
        '\n\n'
        '没执行也能开，但后台读不到内容，功能不会生效。',
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开启'),
        ),
      ],
    ),
  );
  if (agreed != true) return;
  await service.setEnabled(true);
  if (!context.mounted) return;
  showMigaToast(
    context,
    service.canReadInBackground.value
        ? '已开启后台监听剪贴板'
        : '已开启，但后台读取仍被系统禁止（见设置项说明）',
  );
}

/// 重新进行新手引导：清掉「已完成引导」标记，并把设置页及之前的路由一起清掉，
/// 引导页成为新的栈底。牌库与配装好的牌组不受影响。
Future<void> _restartOnboarding(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重新进行新手引导'),
      content: const Text('会回到欢迎页重新走一遍引导流程，牌库和配装好的牌组不会被清除。'),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        M3EFilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开始'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await LocalStore.instance.resetOnboarding();
  onboardingDone = false;
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    (route) => false,
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('设置', style: theme.textTheme.titleLarge)),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 顶部说明卡片（与用户卡片同款，图标为齿轮）
              // 顶部说明卡片（与用户卡片同款，图标为齿轮）
              _settingsSegmented(
                theme: theme,
                color: theme.colorScheme.primaryContainer,
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Icon(
                            Icons.settings,
                            size: 40,
                            color: theme.colorScheme.primaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '设置',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '在这里调整应用的显示与偏好设置，包括深色模式等外观选项。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ---- 外观 ----
              const _SectionTitle('外观'),
              const _MonetThemeCard(),
              const SizedBox(height: 8),
              // 深色模式（开关，整行可点）+ 界面缩放（滑杆）+ 液态玻璃底栏（开关，整行可点）
              //
              // 索引判断按 children 顺序来：0 = 深色模式，1 = 界面缩放（滑杆自己处理手势，
              // 这里不给 onTap），2 = 液态玻璃底栏。加行时必须同步改这两个分支，
              // 否则深色模式的点击会串到新行上。
              // index 0 在液态玻璃开着时要保持空操作（深色模式被锁，见 _DarkModeRow）。
              _settingsSegmented(
                theme: theme,
                isSelected: (i) => switch (i) {
                  0 => themeController.themeMode == ThemeMode.dark,
                  2 => themeController.useLiquidGlassBottomBar,
                  _ => false,
                },
                onTap: (i) {
                  if (i == 0) {
                    // 液态玻璃开着时深色模式被锁住，点它不做任何事（提示见 _DarkModeRow）
                    if (themeController.useLiquidGlassBottomBar) return;
                    themeController.toggleThemeMode();
                  } else if (i == 2) {
                    _toggleLiquidBottomBar(context);
                  }
                },
                // 这几行各自监听 themeController，所以用 const 是安全的
                children: const [
                  _DarkModeRow(),
                  _UiScaleSetting(),
                  _LiquidBottomBarRow(),
                ],
              ),
              const SizedBox(height: 20),
              // ---- 安全 ----
              const _SectionTitle('安全'),
              const _BiometricAuthToggle(),
              const SizedBox(height: 20),
              // ---- 牌桌可视 ----
              const _SectionTitle('牌桌可视'),
              // 开关状态放在各自的服务里：用它们的 ValueNotifier 驱动选中高亮与
              // Switch（父级只监听 themeController，不会因为这些开关变化而重建）。
              ListenableBuilder(
                listenable: Listenable.merge([
                  ClipboardAutoFill.instance.enabled,
                  ClipboardWatchService.instance.enabled,
                  ClipboardWatchService.instance.canReadInBackground,
                ]),
                builder: (context, _) {
                  final autoFill = ClipboardAutoFill.instance.enabled.value;
                  final watch = ClipboardWatchService.instance.enabled.value;
                  final canRead =
                      ClipboardWatchService.instance.canReadInBackground.value;
                  return _settingsSegmented(
                    theme: theme,
                    isSelected: (i) =>
                        (i == 0 && autoFill) || (i == 1 && watch),
                    onTap: (i) {
                      if (i == 0) _toggleClipboardAutoFill(context);
                      if (i == 1) _toggleClipboardWatch(context);
                    },
                    children: [
                      _SegmentedSwitchRow(
                        title: '自动读取剪贴板',
                        subtitle: '剪贴板里出现牌桌数据时自动填充可视页',
                        value: autoFill,
                        // 整行点击由所在分段列的 onTap 处理，这里只作为语义上的开关；
                        // 不传的话 Switch 会走 onChanged == null 的禁用外观（灰掉）。
                        onChanged: (_) => _toggleClipboardAutoFill(context),
                        leading: Icon(
                          Icons.content_paste_search,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _SegmentedSwitchRow(
                        title: '后台监听剪贴板',
                        subtitle: !watch
                            ? '退到后台也能监听，命中后弹横幅通知'
                            : canRead
                            ? '已开启：命中牌桌数据会弹横幅通知'
                            : '已开启，但系统还没允许后台读取（需要执行一次 appops 命令）',
                        value: watch,
                        onChanged: (_) => _toggleClipboardWatch(context),
                        leading: Icon(
                          Icons.notifications_active_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              // ---- 帮助与排查 ----
              const _SectionTitle('帮助与排查'),
              // 重新进行新手引导
              _settingsSegmented(
                theme: theme,
                isSelected: (_) => false,
                onTap: (_) => _restartOnboarding(context),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.restart_alt,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '重新进行新手引导',
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '回到欢迎页重新走一遍引导流程',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 日志导出
              _settingsSegmented(
                theme: theme,
                isSelected: (_) => false,
                onTap: (_) => showLogDialog(context),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bug_report_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('导出日志', style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 2),
                            Text(
                              '保存或分享应用日志，便于排查问题',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 设置页/引导页共用的 M3E 分段卡片列。
///
/// 参数取自 m3e_core 自带的设置页示例
/// `example/lib/shared/segmented_switch_group.dart`，与包内规范保持一致：
/// 外圆角 16 / 相邻未选中内圆角 6 / 选中态形变到 20 / 按下 4，
/// 选中行用 primaryContainer 半透明底高亮。
M3ESegmentedColumn _settingsSegmented({
  required ThemeData theme,
  required List<Widget> children,
  void Function(int index)? onTap,
  bool Function(int index)? isSelected,
  Color? color,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 6,
  ),
}) {
  return M3ESegmentedColumn(
    onTap: onTap,
    isSelected: isSelected,
    selectionMode: M3ESelectionMode.multiple,
    selectionTrigger: M3ESelectionTrigger.none,
    outerRadius: 16,
    innerRadius: 6,
    selectedRadius: 20,
    pressedRadius: 4,
    selectedColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.40),
    // m3e_core 基于 material_ui 分支，splashFactory 必须用该包自己的 InkSparkle
    splashFactory: mui.InkSparkle.splashFactory,
    padding: padding,
    color: color,
    children: children,
  );
}

/// 分段卡片里的一行开关。
///
/// 行结构同包内示例：文字在左、`Switch` 在右且被 [IgnorePointer] 屏蔽手势，
/// 整行点击交给所属分段列的 `onTap` 处理，这样涟漪与按压缩放才落在整行上。
class _SegmentedSwitchRow extends StatelessWidget {
  const _SegmentedSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
    this.leading,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IgnorePointer(child: Switch(value: value, onChanged: onChanged)),
      ],
    );
  }
}

/// 界面缩放设置：整体放大/缩小 UI（含字体），应对不同字体与 DPI
class _UiScaleSetting extends StatelessWidget {
  const _UiScaleSetting();

  // 自己监听 themeController：父级哪怕因为 const 规范化跳过重建，这一行也会更新
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = themeController.uiScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.zoom_out_map, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('界面元素缩放', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    '放大或缩小字体等界面元素，适配不同手机显示偏好',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(scale * 100).round()}%',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        M3ESlider(
          value: scale,
          min: 0.8,
          max: 1.5,
          divisions: 14,
          label: '${(scale * 100).round()}%',
          onChanged: themeController.setUiScale,
        ),
      ],
    );
  }
}

/// 配装页生物识别验证开关（持久化）
class _BiometricAuthToggle extends StatefulWidget {
  const _BiometricAuthToggle();

  @override
  State<_BiometricAuthToggle> createState() => _BiometricAuthToggleState();
}

class _BiometricAuthToggleState extends State<_BiometricAuthToggle> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    LocalStore.instance.isDeckAuthEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool value) async {
    // 关闭验证必须先通过生物识别，防止他人直接关掉保护
    if (!value) {
      final ok = await authenticateBiometric('关闭身份验证前请先验证身份');
      if (!ok || !mounted) {
        if (mounted) {
          showMigaToast(context, '验证失败，未关闭身份验证');
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _enabled = value);
    await LocalStore.instance.setDeckAuthEnabled(value);
    if (mounted) {
      showMigaToast(context, value ? '已开启生物识别验证' : '已关闭生物识别验证');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _settingsSegmented(
      theme: Theme.of(context),
      isSelected: (_) => _enabled,
      onTap: (_) => _toggle(!_enabled),
      children: [
        _SegmentedSwitchRow(
          title: '配装页身份验证',
          subtitle: '进入配装页时使用指纹/人脸验证身份',
          value: _enabled,
          onChanged: _toggle,
          leading: const Icon(Icons.fingerprint),
        ),
      ],
    );
  }
}

/// 主题设置：莫奈取色 + 默认配色方案（M3E 可展开卡片）
///
/// 展开 = 关闭系统取色并显示默认配色方案；收起 = 开启系统取色。
class _MonetThemeCard extends StatelessWidget {
  const _MonetThemeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useMonet = themeController.useMonet;
    final cs = theme.colorScheme;
    return M3EExpandableCardColumn(
      initiallyExpanded: useMonet ? const {} : const {0},
      style: const M3EExpandableStyle(
        outerRadius: 16,
        innerRadius: 6,
        gap: 0,
        expandedRadius: 16,
      ),
      onExpansionChanged: (_, isExpanded) {
        if (themeController.useMonet == isExpanded) {
          themeController.setUseMonet(!isExpanded);
        }
      },
      data: [
        M3EExpandableData(
          title: '莫奈取色系统',
          subtitle: useMonet
              ? '已开启系统动态取色，展开可自定义默认配色'
              : '已关闭系统动态取色，使用下方默认配色方案',
          leading: Icon(
            Icons.auto_awesome,
            color: useMonet ? cs.primary : cs.outlineVariant,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '什么是莫奈取色',
            onPressed: () => _showMonetHelp(context),
          ),
          bodyBuilder: (_) => _buildSchemeConfig(theme),
        ),
      ],
    );
  }

  Widget _buildSchemeConfig(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '默认配色方案',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text('种子颜色', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in _seedColors)
              _ColorDot(
                color: c,
                selected: themeController.seedColor == c,
                onTap: () => themeController.setSeedColor(c),
              ),
          ],
        ),
        const Divider(height: 28),
        Text('色彩风格', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in _schemeVariants.entries)
              ChoiceChip(
                label: Text(v.value),
                selected: themeController.schemeVariant == v.key,
                onSelected: (_) => themeController.setSchemeVariant(v.key),
              ),
          ],
        ),
      ],
    );
  }
}

/// 深色模式开关（分段卡片里的一行）
class _DarkModeRow extends StatelessWidget {
  const _DarkModeRow();

  // 自己监听 themeController：父级哪怕因为 const 规范化跳过重建，这一行也会更新
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    // 液态玻璃底栏开着时锁住深色模式：玻璃只在深色下可读，不能让用户关掉
    final locked = themeController.useLiquidGlassBottomBar;
    final row = _SegmentedSwitchRow(
      title: '深色模式',
      subtitle: '切换深浅主题',
      value: themeController.themeMode == ThemeMode.dark,
      // null 让 Switch 呈禁用外观；整行点击由分段列的 onTap(0) 拦截
      onChanged: locked ? null : (_) => themeController.toggleThemeMode(),
    );
    if (!locked) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        const SizedBox(height: 2),
        Text(
          '该选项现在受其他设置项控制',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 底栏外观开关（分段卡片里的一行）：用 Liquid Glass 替换 M3E 浮动工具栏
class _LiquidBottomBarRow extends StatelessWidget {
  const _LiquidBottomBarRow();

  // 自己监听 themeController：父级哪怕因为 const 规范化跳过重建，这一行也会更新
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    return _SegmentedSwitchRow(
      title: '液态玻璃底栏',
      subtitle: '用 Liquid Glass 替换 M3E 底栏',
      value: themeController.useLiquidGlassBottomBar,
      // 整行点击由所在分段列的 onTap 处理，这里只作为语义上的开关
      onChanged: (_) => themeController.setBottomBarStyle(
        themeController.useLiquidGlassBottomBar
            ? kBottomBarStyleM3E
            : kBottomBarStyleLiquid,
      ),
    );
  }
}

/// 主题设置组件（设置页与引导页共用）：莫奈取色 + 深色模式
class _ThemeSettingsSection extends StatelessWidget {
  const _ThemeSettingsSection();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => Column(
        children: [
          const _MonetThemeCard(),
          const SizedBox(height: 16),
          _settingsSegmented(
            theme: Theme.of(context),
            isSelected: (_) => themeController.themeMode == ThemeMode.dark,
            onTap: (_) {
              // 与设置页一致：玻璃开着时深色模式锁定
              if (themeController.useLiquidGlassBottomBar) return;
              themeController.toggleThemeMode();
            },
            children: const [_DarkModeRow()],
          ),
        ],
      ),
    );
  }
}

void _showMonetHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('什么是莫奈取色'),
      content: const Text(
        '「莫奈取色」（Material You 动态取色）会从你的系统壁纸或主题中提取主色调，'
        '自动生成一套与之协调的应用配色，让应用外观跟随系统一起变化。'
        '\n\n'
        '开启后应用将跟随系统的动态取色；关闭后则使用下面手动选择的默认配色方案。',
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 引导页统一外壳：内容整体靠**左下**（底部留出 FAB 那一带的高度，免得被压住），
/// 小屏内容超高时可以滚动；[trailing] 会落在右下角、FAB 的正上方。
class _OnboardingPane extends StatelessWidget {
  const _OnboardingPane({required this.children, this.trailing});

  final List<Widget> children;
  final Widget? trailing;

  /// 底部留白：底部导航 FAB（位于 bottom 48 + 高 56）之上再留一点间隙
  static const _bottomInset = 120.0;

  @override
  Widget build(BuildContext context) {
    // 有右下角按钮时，内容底部再让出一条按钮的高度，免得文字压在按钮下面
    final contentBottom = _bottomInset + (trailing != null ? 56.0 : 0.0);
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, contentBottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - 24 - contentBottom,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (trailing != null)
          Positioned(right: 24, bottom: _bottomInset, child: trailing!),
      ],
    );
  }
}

/// 引导页第 4 屏：进入即自动从 CDN 更新牌库。
///
/// 进度用 M3E 加载指示器；失败给原因 + 重试，可以直接跳过（配装页菜单里还有入口）。
class _AutoLibraryUpdatePage extends StatefulWidget {
  const _AutoLibraryUpdatePage();

  @override
  State<_AutoLibraryUpdatePage> createState() => _AutoLibraryUpdatePageState();
}

class _AutoLibraryUpdatePageState extends State<_AutoLibraryUpdatePage> {
  LibraryUpdateResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = null;
    });
    final result = await LibraryUpdater.instance.update();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  String get _message {
    final result = _result;
    if (result == null) return '正在从官方地址获取最新牌库…';
    return switch (result.status) {
      LibraryUpdateStatus.updated =>
        '牌库已更新到 v${result.version}（${result.count} 张卡牌）',
      LibraryUpdateStatus.upToDate => '已是最新版本 v${result.version}',
      LibraryUpdateStatus.busy => '正在更新牌库…',
      LibraryUpdateStatus.failed => '更新失败：${result.message}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = _result?.status == LibraryUpdateStatus.failed;
    return _OnboardingPane(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.cloud_sync_outlined,
            size: 48,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '自动更新牌库',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '牌库由官方统一维护，进入这一屏会自动获取最新版本。\n'
          '跳过也没关系，之后可以在配装页右上角菜单里手动更新。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        if (_running)
          // shapes 非空时不能 const（内部 assert 会读 shapes.length）
          M3ELoadingIndicator(
            shapes: const [Shapes.softBurst, Shapes.sunny, Shapes.pill],
            constraints: const BoxConstraints.tightFor(
              width: 56.00,
              height: 56.00,
            ),
            semanticsLabel: 'Loading',
            semanticsValue: 'In progress',
          )
        else
          Icon(
            failed ? Icons.error_outline : Icons.check_circle_outline,
            size: 56,
            color: failed
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
        const SizedBox(height: 16),
        Text(_message, style: theme.textTheme.bodyMedium),
        if (failed) ...[
          const SizedBox(height: 20),
          M3EFilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ],
    );
  }
}

/// 我们的优势页：清屏进入 → 四张卡片 2x2 缓慢逐张浮现 → 全部浮现后出现「我已了解」
class _AdvantagesPage extends StatefulWidget {
  const _AdvantagesPage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<_AdvantagesPage> createState() => _AdvantagesPageState();
}

class _AdvantagesPageState extends State<_AdvantagesPage>
    with TickerProviderStateMixin {
  static const _items = [
    (Icons.money_off, '完全免费', '所以求求你们赞助我！'),
    (
      Icons.groups,
      '玩家社区深度绑定',
      '得益于我们优秀便捷的牌组导入导出系统，你可以与小伙伴或社区中其他玩家分享你的强力卡组，或者使用其他玩家分享给你的卡组！',
    ),
    (
      Icons.auto_awesome,
      '一站式的便捷流程',
      '本APP已整合社区的腾讯频道，你可以在首页浏览玩家们发布的帖子，以及及时使用置顶帖子更新你的牌库！',
    ),
    (Icons.palette, 'Material Design', '该APP界面完全使用谷歌Material Design，美观高效，赏心悦目'),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _fadeOut = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  bool _showButton = false;

  @override
  void initState() {
    super.initState();
    // 先保持全屏空白，等待一段时间后再开始浮现
    Future.delayed(const Duration(milliseconds: 1200)).then((_) {
      if (!mounted) return;
      _controller.forward().whenComplete(() {
        if (mounted) setState(() => _showButton = true);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (_fadeOut.isAnimating) return;
    // 全部组件淡出后再进入下一页
    _fadeOut.forward().whenComplete(() {
      if (mounted) widget.onContinue();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _fadeOut,
      builder: (context, _) {
        return Opacity(
          opacity: (1 - _fadeOut.value).clamp(0.0, 1.0),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.05, 0.2, curve: Curves.easeOut),
                      ),
                      child: Text(
                        '亮点介绍',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.92,
                          children: [
                            for (var i = 0; i < _items.length; i++)
                              _AdvantageCard(
                                icon: _items[i].$1,
                                label: _items[i].$2,
                                description: _items[i].$3,
                                progress: Curves.easeOut.transform(
                                  Interval(
                                    i * 0.15 + 0.15,
                                    math.min(0.6 + i * 0.15, 0.95),
                                    curve: Curves.easeOut,
                                  ).transform(_controller.value),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // 全部浮现后出现的「我已了解」（FAB）
                    AnimatedOpacity(
                      opacity: _showButton ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: M3EFloatingActionButton(
                        onPressed: _onContinue,
                        tooltip: '我已了解',
                        child: const Icon(Icons.check),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 欢迎使用谜咖：淡入，仅「开始使用」按钮
class _WelcomePage extends StatefulWidget {
  const _WelcomePage({required this.onStart});

  final VoidCallback onStart;

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      // 内容靠左下；「开始使用」只留右下角这一个按钮（之前和 FAB 重复了）
      child: _OnboardingPane(
        trailing: M3EFilledButton.icon(
          onPressed: widget.onStart,
          icon: const Icon(Icons.rocket_launch),
          label: const Text('开始使用'),
        ),
        children: [
          Text(
            '欢迎使用谜咖',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '开始你的游戏之旅吧',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvantageCard extends StatelessWidget {
  const _AdvantageCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final String description;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opacity = progress.clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 16),
        child: Transform.scale(
          scale: 0.9 + 0.1 * opacity,
        child: M3ECard(
          index: 0,
          position: M3ECardPosition.single,
          outerRadius: 12,
          innerRadius: 4,
          gap: 0,
          padding: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// 主页下方内嵌 WebView（Android/iOS 用内嵌；桌面端回退为外部浏览器打开）
class _HomeWebView extends StatefulWidget {
  const _HomeWebView({required this.url});

  final String url;

  @override
  State<_HomeWebView> createState() => _HomeWebViewState();
}

class _HomeWebViewState extends State<_HomeWebView> {
  bool _loading = true;
  bool _failed = false;

  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _loading = true;
              _failed = false;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) {
            setState(() {
              _loading = false;
              _failed = false;
            });
          }
        },
        // 主页面无法访问（DNS/连接失败/未知协议等）时自动返回上一页；
        // 没有可返回的历史就转到错误态，不要一直停在 WebView 的纯白底
        onWebResourceError: (error) async {
          final unreachable =
              error.isForMainFrame == true &&
              (error.errorType == WebResourceErrorType.hostLookup ||
                  error.errorType == WebResourceErrorType.connect ||
                  error.errorType == WebResourceErrorType.unsupportedScheme ||
                  error.errorType == WebResourceErrorType.badUrl);
          if (!unreachable) return;
          if (await _controller.canGoBack()) {
            await _controller.goBack();
            return;
          }
          if (mounted) {
            setState(() {
              _loading = false;
              _failed = true;
            });
          }
        },
      ),
    )
    ..loadRequest(Uri.parse(widget.url));

  void _reload() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final theme = Theme.of(context);
    if (isMobile) {
      return Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          // 加载/失败占位：WebView 自身底色是纯白，页面画出来之前先盖住
          if (_loading || _failed)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: Center(
                  child: _failed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_off,
                              size: 36,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '社区页面加载失败',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            M3EFilledButton(
                              onPressed: _reload,
                              child: const Text('重试'),
                            ),
                          ],
                        )
                      // 加载动画换成 M3E 的形变加载指示器：尺寸沿用原来的 28x28 占位，
                      // 不套用整页/大块场景的 56x56，避免把 WebView 遮罩内的布局撑大。
                      // 此处不能加 const：M3ELoadingIndicator 的断言里访问了 shapes.length，
                      // 传了非空 shapes 时无法作为常量表达式求值。
                      : SizedBox(
                          width: 28,
                          height: 28,
                          child: M3ELoadingIndicator(
                            shapes: const [
                              Shapes.softBurst,
                              Shapes.sunny,
                              Shapes.pill,
                            ],
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                            semanticsLabel: 'Loading',
                            semanticsValue: 'In progress',
                          ),
                        ),
                ),
              ),
            ),
          // 内嵌网页返回键（常驻，右上角，无背景，深色图标）
          Positioned(
            top: 12,
            right: 50,
            child: IconButton(
              onPressed: () async {
                if (await _controller.canGoBack()) {
                  _controller.goBack();
                }
              },
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.black87,
                size: 28,
              ),
            ),
          ),
        ],
      );
    }
    // 桌面端无内嵌 WebView，打开内置 WebKit 网页窗口
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: M3EFilledButton.icon(
        onPressed: _openDesktopWebview,
        icon: const Icon(Icons.open_in_new),
        label: const Text('打开内置网页'),
      ),
    );
  }

  /// 桌面端：用 WebKitGTK 打开独立的网页窗口（真正的 WebView）。
  Future<void> _openDesktopWebview() async {
    try {
      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          title: 'MIGA-谜咖 社区',
          windowWidth: 1100,
          windowHeight: 800,
          useWindowPositionAndSize: false,
        ),
      );
      webview.launch(widget.url);
    } catch (e) {
      if (mounted) {
        showMigaToast(context, '无法打开内置网页');
      }
    }
  }
}

/// 赞助页：微信 / 支付宝收款码
class SponsorPage extends StatelessWidget {
  const SponsorPage({super.key});

  void _showQr(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String asset,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 8),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  asset,
                  width: 240,
                  height: 240,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '请使用 $title 扫码赞助，感谢支持！',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('我需要您的支持！', style: theme.textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部介绍卡片（与其他页面同款）
          M3ECard(
            index: 0,
            position: M3ECardPosition.single,
            outerRadius: 16,
            innerRadius: 4,
            gap: 0,
            padding: EdgeInsets.zero,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Icon(
                      Icons.favorite,
                      size: 40,
                      color: theme.colorScheme.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '赞助',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这个项目由晓周个人驱动，永久免费，使用全程不会收取您任何费用，也永远不会有植入式广告，赞助是我唯一的盈利方式！如果您手头富裕，欢迎付给我任意金额的赞助，您的赞助用于维持这个项目正常开发，感谢您的支持！',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: M3EFilledButton.icon(
                  onPressed: () => _showQr(
                    context,
                    '微信',
                    Icons.wechat,
                    const Color(0xFF07C160),
                    'assets/qrcodes/wechat.png',
                  ),
                  icon: const Icon(Icons.wechat),
                  label: const Text('微信'),
                  decoration: M3EButtonDecoration.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M3EFilledButton.icon(
                  onPressed: () => _showQr(
                    context,
                    '支付宝',
                    Icons.account_balance_wallet,
                    const Color(0xFF1677FF),
                    'assets/qrcodes/alipay.jpg',
                  ),
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('支付宝（推荐）'),
                  decoration: M3EButtonDecoration.styleFrom(
                    backgroundColor: const Color(0xFF1677FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 赞助安全提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '本人赞助方式目前只有该页面的两个收款码，请勿在其他渠道付款赞助！！！',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
