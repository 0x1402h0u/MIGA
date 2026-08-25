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

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:local_auth/local_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'data/card_pool.dart';
import 'data/deck_pool.dart';
import 'data/local_store.dart';
import 'data/player_profile.dart';
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

/// 是否已完成新手引导（首次启动时 false，显示引导页）
bool onboardingDone = false;

/// 上次对局未完成时保存的手牌快照（应用被杀后重启时提示恢复）
PendingHand? pendingHand;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogCollector.instance.init();
  await _loadPersistedData();
  onboardingDone = await LocalStore.instance.isOnboardingDone();
  pendingHand = await LocalStore.instance.loadPendingHand();
  LogCollector.instance.log(
    '启动完成：牌库 ${CardPool.instance.cards.length} 张，'
    '卡组 ${DeckPool.instance.savedDecks.length} 个',
  );
  // 用 zone 接管 print 与未捕获异常，扩大日志抓取范围
  runZonedGuarded(
    () => runApp(const MigaApp()),
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
              // 语言选择（目前仅提供中文，默认选中）
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                          onChanged: (v) =>
                              setState(() => _language = v ?? 'zh'),
                          child: const RadioListTile<String>(
                            value: 'zh',
                            title: Text('中文'),
                            subtitle: Text('简体中文 🇨🇳'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 选择主题：莫奈取色开关 + 默认配色方案 + 深色模式
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                  ),
                ),
              ),
              // 初次导入牌库（可跳过，之后在配装页仍有入口）
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.data_object,
                            size: 48,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '导入牌库',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'JSON 卡牌牌库由官方统一提供，\n导入后即可在配装页选配牌组。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        M3EFilledButton.icon(
                          onPressed: () => importCardLibrary(context),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('导入卡牌JSON'),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '跳过也没关系，你下次可以在配装页面再次看到这个入口。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 赞助页入口
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        M3EFilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SponsorPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.favorite),
                          label: const Text('打开赞助页面'),
                        ),
                      ],
                    ),
                  ),
                ),
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
                      M3EFilledButton(onPressed: _next, child: Text(_nextLabel)),
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

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final TabController _tabController;

  static const _titles = ['我们的征途是星辰大海', '配装', '发牌', '解析'];

  final _deckConfigKey = GlobalKey<DeckConfigScreenState>();
  final _drawKey = GlobalKey<DrawScreenState>();

  /// 配装页右上角 M3E 下拉菜单控制器：每次动作后清空选中，避免重建时重复触发
  final _deckMenuController = M3EDropdownController<String>();

  /// 本次会话是否已通过配装页身份验证
  bool _deckAuthPassed = false;

  /// 发牌对局是否进行中（手牌非空）：进行中禁用 Tab 滑动切换，防误触
  bool _drawInGame = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _titles.length, vsync: this);
    // 滑动 Tab 切换不经过 TabBar.onTap，需要监听控制器同步页面与身份验证
    _tabController.addListener(_syncTabFromController);
    // 上次对局未完成：首帧后弹窗询问是否恢复
    if (pendingHand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptResumeHand());
    }
  }

  void _onDrawInGameChanged(bool v) {
    if (_drawInGame != v) setState(() => _drawInGame = v);
  }

  /// 用户滑动 TabBarView 时控制器索引会直接变化（不经过 onTap），
  /// 这里同步页面状态并执行与点按一致的校验/回退
  void _syncTabFromController() {
    if (_tabController.indexIsChanging) return;
    final i = _tabController.index;
    if (i == _currentIndex) return;
    unawaited(_handleSwipeTab(i));
  }

  Future<void> _handleSwipeTab(int i) async {
    final ok = await _trySelect(i);
    if (!ok && mounted) {
      // 校验失败：把索引回退到当前页
      _tabController.index = _currentIndex;
    }
  }

  @override
  void dispose() {
    _deckMenuController.dispose();
    _tabController.removeListener(_syncTabFromController);
    _tabController.dispose();
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
      // 发牌页在 Tab 动画过程中才创建，等动画结束后再恢复
      _tabController.animateTo(2);
      final anim = _tabController.animation;
      late final void Function(AnimationStatus) onDone;
      onDone = (status) {
        if (status != AnimationStatus.completed) return;
        anim?.removeStatusListener(onDone);
        if (!mounted) return;
        // 该帧里发牌页刚构建，等本帧结束再读取其状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final drawState = _drawKey.currentState;
          if (drawState == null || !drawState.restorePendingHand(saved)) {
            unawaited(LocalStore.instance.clearPendingHand());
          }
        });
      };
      anim?.addStatusListener(onDone);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('牌库已清空')));
    }
  }

  /// 配装页右上角菜单的菜单项（牌库操作 + 卡组操作）
  static const List<M3EDropdownItem<String>> _deckMenuItems = [
    M3EDropdownItem(label: '牌库操作', value: 'hdr_lib', disabled: true),
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
        bottom: TabBar(
          controller: _tabController,
          onTap: (i) async {
            final ok = await _trySelect(i);
            if (!ok) {
              // 取消切换：把 Tab 索引回退
              _tabController.index = _currentIndex;
            }
          },
          tabs: const [
            Tab(icon: Icon(Icons.home_outlined), text: '主页'),
            Tab(icon: Icon(Icons.construction_outlined), text: '配装'),
            Tab(icon: Icon(Icons.back_hand), text: '发牌'),
            Tab(icon: Icon(Icons.analytics_outlined), text: '解析'),
          ],
        ),
        actions: [
          // 发牌页帮助按钮（仅发牌 Tab 显示）
          if (_currentIndex == 2)
            IconButton(
              tooltip: '帮助',
              onPressed: _drawKey.currentState?.showDrawHelp,
              icon: const Icon(Icons.help_outline),
            ),
          // 配装页右上角菜单：牌库操作 + 卡组操作（M3E 下拉菜单）
          if (_currentIndex == 1)
            SizedBox(
              width: 184,
              child: M3EDropdownMenu<String>(
                controller: _deckMenuController,
                items: _deckMenuItems,
                singleSelect: true,
                containerRadius: 12,
                // 默认 splash 是 NoSplash（无波纹），这里开启 InkRipple；
                // 字段本身透明（无大按钮背景），只显示右侧三个点图标，
                // 宽度 184 保持菜单面板能完整放下文字项
                splashFactory: mui.InkRipple.splashFactory,
                fieldStyle: const M3EDropdownFieldStyle(
                  suffixIcon: Icon(Icons.more_vert),
                  showArrow: false,
                  hintText: '',
                  backgroundColor: Colors.transparent,
                  border: BorderSide.none,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                itemBuilder: (item, selected, onTap) {
                  if (item.disabled) {
                    final cs = Theme.of(context).colorScheme;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  // 每个菜单项要有自己的 Material，波纹才画在自身表面而非面板底下
                  return Material(
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      onTap: onTap,
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
                  );
                },
                onSelectionChanged: (sel) {
                  if (sel.isEmpty) return;
                  final value = sel.first.value;
                  // 动作菜单：执行后清空选中，避免重建时 setItems 重复触发动作
                  _deckMenuController.clearAll();
                  _handleDeckAction(value);
                },
              ),
            ),
        ],
      ),
      // Tab 可滑动切换；发牌对局进行中禁用滑动，防止误触
      body: TabBarView(
        controller: _tabController,
        physics: _drawInGame
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        children: [
          for (var i = 0; i < _titles.length; i++)
            _KeepAlive(
              child: TickerMode(
                enabled: i == _tabController.index,
                child: _pages[i],
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
        DrawScreen(
          key: _drawKey,
          embedded: true,
          onInGameChanged: _onDrawInGameChanged,
        ),
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
          ],
        ),
      ),
    );
  }
}

/// 常驻页面栈：全部页面首帧构建，切页只切换可见性与动画开关
/// 让 TabBarView 子页常驻内存，避免切页时销毁重建、丢失状态
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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

/// 解析页：上方三数值（骨头/能量/玛珂）+ 手牌数 + 横向滑动卡牌，
/// 中间天平，下方为对称布局，上下卡牌同步滚动。
class _AnalyzePage extends StatefulWidget {
  const _AnalyzePage();

  @override
  State<_AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<_AnalyzePage>
    with AutomaticKeepAliveClientMixin {
  static const _cardW = 120.0;
  static const _cardH = 168.0;

  final _topScroll = ScrollController();
  final _bottomScroll = ScrollController();
  bool _syncing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 上下卡牌滚动同步
    _topScroll.addListener(() => _sync(_topScroll, _bottomScroll));
    _bottomScroll.addListener(() => _sync(_bottomScroll, _topScroll));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _topScroll.dispose();
    _bottomScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final hand = DeckPool.instance.cards;
    final handCount = hand.length;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上半：数值 → 手牌数 → 卡牌
              _halfSection(
                theme,
                hand,
                handCount,
                flipped: false,
                controller: _topScroll,
              ),
              // 天平（左右各 5 档）
              const _BalanceScale(left: 3, right: 3),
              // 下半：对称倒序
              _halfSection(
                theme,
                hand,
                handCount,
                flipped: true,
                controller: _bottomScroll,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _halfSection(
    ThemeData theme,
    List<CardData> hand,
    int handCount, {
    required bool flipped,
    required ScrollController controller,
  }) {
    final resources = Row(
      children: [
        for (final (icon, label) in [
          (Icons.blur_on, '骨头'),
          (Icons.bolt, '能量'),
          (Icons.auto_awesome, '玛珂'),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _resourceChip(theme, icon, label, '0'),
            ),
          ),
      ],
    );
    final countText = Text(
      '手牌数 $handCount',
      style: theme.textTheme.titleMedium,
    );
    final cards = SizedBox(
      height: _cardH,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: _cardW,
            height: _cardH,
            child: i < hand.length
                ? _miniCard(theme, hand[i])
                : _emptyCard(theme),
          ),
        ),
      ),
    );

    return Column(
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
  }

  Widget _resourceChip(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(ThemeData theme, CardData card) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
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
      ),
    );
  }

  Widget _emptyCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

/// 天平：左右各 5 档（圆点档位），圆环指示器套住当前刻度，两侧按键微调。
class _BalanceScale extends StatefulWidget {
  const _BalanceScale({required this.left, required this.right});

  /// 左 / 右档位（0~5）
  final int left;
  final int right;

  @override
  State<_BalanceScale> createState() => _BalanceScaleState();
}

class _BalanceScaleState extends State<_BalanceScale> {
  late int _diff = widget.left - widget.right;

  void _shift(int delta) {
    setState(() => _diff = (_diff + delta).clamp(-5, 5));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final left = _diff > 0 ? _diff : 0;
    final right = _diff < 0 ? -_diff : 0;
    final leftColor = cs.primary;
    final rightColor = cs.error;
    final track = cs.surfaceContainerHighest;
    final outline = cs.outline;

    // 进度条：左右各 5 段从中心向外填充，圆环滑块指示当前位置
    Widget segment(int idx, int count, Color color) {
      return Expanded(
        child: ColoredBox(
          color: idx < count
              ? color.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      );
    }

    final bar = Container(
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outline.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.10),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++) segment(4 - i, left, leftColor),
              const SizedBox(width: 1, height: 32),
              for (var i = 0; i < 5; i++) segment(i, right, rightColor),
            ],
          ),
          // 长条滑块（沿条移动，等高于条）
          AnimatedAlign(
            alignment: Alignment(_diff / 5, 0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: _diff == 0
                    ? outline
                    : (_diff > 0 ? leftColor : rightColor),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: _diff <= -5 ? null : () => _shift(-1),
          icon: const Icon(Icons.arrow_back),
          tooltip: '左倾',
        ),
        const SizedBox(width: 12),
        SizedBox(width: 200, child: bar),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: _diff >= 5 ? null : () => _shift(1),
          icon: const Icon(Icons.arrow_forward),
          tooltip: '右倾',
        ),
      ],
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
              ),
              const SizedBox(height: 20),
              // ---- 外观 ----
              const _SectionTitle('外观'),
              const _MonetThemeCard(),
              const SizedBox(height: 8),
              const M3ECardColumn(
                outerRadius: 16,
                innerRadius: 4,
                gap: 8,
                padding: EdgeInsets.zero,
                children: [
                  // 深色模式
                  _DarkModeThemeCard(),
                  // 界面缩放
                  _UiScaleSetting(),
                ],
              ),
              const SizedBox(height: 20),
              // ---- 安全 ----
              const _SectionTitle('安全'),
              const M3ECard(
                index: 0,
                position: M3ECardPosition.single,
                outerRadius: 16,
                innerRadius: 4,
                gap: 0,
                padding: EdgeInsets.zero,
                child: _BiometricAuthToggle(),
              ),
              const SizedBox(height: 20),
              // ---- 帮助与排查 ----
              const _SectionTitle('帮助与排查'),
              M3ECard(
                index: 0,
                position: M3ECardPosition.single,
                outerRadius: 16,
                innerRadius: 4,
                gap: 0,
                padding: EdgeInsets.zero,
                // 日志导出
                child: ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('导出日志'),
                  subtitle: const Text('保存或分享应用日志，便于排查问题'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLogDialog(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 界面缩放设置：整体放大/缩小 UI（含字体），应对不同字体与 DPI
class _UiScaleSetting extends StatelessWidget {
  const _UiScaleSetting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = themeController.uiScale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.zoom_out_map),
            title: Text('界面元素缩放', style: theme.textTheme.bodyLarge),
            subtitle: Text(
              '放大或缩小字体等界面元素，适配不同手机显示偏好',
              style: theme.textTheme.bodySmall,
            ),
            trailing: Text(
              '${(scale * 100).round()}%',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
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
      ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('验证失败，未关闭身份验证')));
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _enabled = value);
    await LocalStore.instance.setDeckAuthEnabled(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? '已开启生物识别验证' : '已关闭生物识别验证')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      title: Text('配装页身份验证', style: theme.textTheme.bodyLarge),
      subtitle: Text('进入配装页时使用指纹/人脸验证身份', style: theme.textTheme.bodySmall),
      secondary: const Icon(Icons.fingerprint),
      value: _enabled,
      onChanged: _toggle,
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

/// 深色模式开关（一张卡片的内容）
class _DarkModeThemeCard extends StatelessWidget {
  const _DarkModeThemeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      title: Text('深色模式', style: theme.textTheme.bodyLarge),
      subtitle: Text('切换深浅主题', style: theme.textTheme.bodySmall),
      value: themeController.themeMode == ThemeMode.dark,
      onChanged: (_) => themeController.toggleThemeMode(),
    );
  }
}

/// 主题设置组件（设置页与引导页共用）：莫奈取色 + 深色模式两张卡片
class _ThemeSettingsSection extends StatelessWidget {
  const _ThemeSettingsSection();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => const Column(
        children: [
          _MonetThemeCard(),
          SizedBox(height: 16),
          M3ECard(
            index: 0,
            position: M3ECardPosition.single,
            outerRadius: 16,
            innerRadius: 4,
            gap: 0,
            padding: EdgeInsets.zero,
            child: _DarkModeThemeCard(),
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
                    // 全部浮现后出现的「我已了解」
                    AnimatedOpacity(
                      opacity: _showButton ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      child: M3EFilledButton(
                        onPressed: _onContinue,
                        child: const Text('我已了解'),
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
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.rocket_launch,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 32),
              M3EFilledButton(
                onPressed: widget.onStart,
                child: const Text('开始使用'),
              ),
            ],
          ),
        ),
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
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        // 主页面无法访问（DNS/连接失败/未知协议等）时自动返回上一页
        onWebResourceError: (error) async {
          final unreachable =
              error.isForMainFrame == true &&
              (error.errorType == WebResourceErrorType.hostLookup ||
                  error.errorType == WebResourceErrorType.connect ||
                  error.errorType == WebResourceErrorType.unsupportedScheme ||
                  error.errorType == WebResourceErrorType.badUrl);
          if (unreachable) {
            if (await _controller.canGoBack()) {
              _controller.goBack();
            }
          }
        },
      ),
    )
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      return Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开内置网页')));
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
