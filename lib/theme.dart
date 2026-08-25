import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart' as m3e;
import 'package:m3e_design/m3e_design.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'data/local_store.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  bool _useMonet = false;
  Color _seedColor = Colors.deepPurple;
  DynamicSchemeVariant _schemeVariant = DynamicSchemeVariant.tonalSpot;
  double _uiScale = 1.0;

  ThemeMode get themeMode => _themeMode;
  bool get useMonet => _useMonet;
  Color get seedColor => _seedColor;
  DynamicSchemeVariant get schemeVariant => _schemeVariant;

  /// 界面缩放系数（0.8 ~ 1.5，1.0 为默认）
  double get uiScale => _uiScale;

  /// 启动时从本地恢复界面缩放
  Future<void> loadUiScale() async {
    _uiScale = await LocalStore.instance.getUiScale();
    notifyListeners();
  }

  /// 启动时从本地恢复主题设置（深色模式 / 莫奈 / 种子色 / 色彩风格）
  Future<void> loadTheme() async {
    final mode = await LocalStore.instance.getThemeMode();
    if (mode != null) {
      _themeMode = switch (mode) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    }
    _useMonet = await LocalStore.instance.getUseMonet();
    _seedColor = Color(await LocalStore.instance.getSeedColor());
    final variant = await LocalStore.instance.getSchemeVariant();
    if (variant != null) {
      _schemeVariant = switch (variant) {
        'content' => DynamicSchemeVariant.content,
        'expressive' => DynamicSchemeVariant.expressive,
        'fidelity' => DynamicSchemeVariant.fidelity,
        'fruitSalad' => DynamicSchemeVariant.fruitSalad,
        'monochrome' => DynamicSchemeVariant.monochrome,
        'neutral' => DynamicSchemeVariant.neutral,
        'rainbow' => DynamicSchemeVariant.rainbow,
        'vibrant' => DynamicSchemeVariant.vibrant,
        _ => DynamicSchemeVariant.tonalSpot,
      };
    }
    notifyListeners();
  }

  void setUiScale(double value) {
    value = value.clamp(0.8, 1.5);
    if (_uiScale == value) return;
    _uiScale = value;
    LocalStore.instance.setUiScale(value);
    notifyListeners();
  }

  void toggleThemeMode() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    LocalStore.instance.setThemeMode(
      _themeMode == ThemeMode.dark ? 'dark' : 'light',
    );
    notifyListeners();
  }

  void setUseMonet(bool value) {
    if (_useMonet == value) return;
    _useMonet = value;
    LocalStore.instance.setUseMonet(value);
    notifyListeners();
  }

  void setSeedColor(Color value) {
    if (_seedColor == value) return;
    _seedColor = value;
    LocalStore.instance.setSeedColor(value.toARGB32());
    notifyListeners();
  }

  void setSchemeVariant(DynamicSchemeVariant value) {
    if (_schemeVariant == value) return;
    _schemeVariant = value;
    LocalStore.instance.setSchemeVariant(value.name);
    notifyListeners();
  }
}

/// 按比例缩放整套文字样式（仅缩放已有 fontSize 的样式）
TextTheme _scaleTextTheme(TextTheme t, double s) {
  TextStyle? f(TextStyle? ts) => ts?.copyWith(fontSize: (ts.fontSize ?? 14.0) * s);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

class _SeedSchemeCache {
  static Color? _seed;
  static DynamicSchemeVariant? _variant;
  static ColorScheme? _light;
  static ColorScheme? _dark;

  static ColorScheme get(Brightness brightness, Color seed, DynamicSchemeVariant variant) {
    if (seed != _seed || variant != _variant) {
      _seed = seed;
      _variant = variant;
      _light = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        dynamicSchemeVariant: variant,
      );
      _dark = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: variant,
      );
    }
    return brightness == Brightness.dark ? _dark! : _light!;
  }
}

/// 把 Flutter 的 [ColorScheme] 转成 material_ui 的配色（字段一一对应）。
mui.ColorScheme _toMuiScheme(ColorScheme cs) {
  return mui.ColorScheme(
    brightness: cs.brightness,
    primary: cs.primary,
    onPrimary: cs.onPrimary,
    primaryContainer: cs.primaryContainer,
    onPrimaryContainer: cs.onPrimaryContainer,
    secondary: cs.secondary,
    onSecondary: cs.onSecondary,
    secondaryContainer: cs.secondaryContainer,
    onSecondaryContainer: cs.onSecondaryContainer,
    tertiary: cs.tertiary,
    onTertiary: cs.onTertiary,
    tertiaryContainer: cs.tertiaryContainer,
    onTertiaryContainer: cs.onTertiaryContainer,
    error: cs.error,
    onError: cs.onError,
    errorContainer: cs.errorContainer,
    onErrorContainer: cs.onErrorContainer,
    surface: cs.surface,
    onSurface: cs.onSurface,
    onSurfaceVariant: cs.onSurfaceVariant,
    outline: cs.outline,
    outlineVariant: cs.outlineVariant,
    shadow: cs.shadow,
    inverseSurface: cs.inverseSurface,
    onInverseSurface: cs.onInverseSurface,
    inversePrimary: cs.inversePrimary,
    surfaceTint: cs.surfaceTint,
    surfaceContainerLowest: cs.surfaceContainerLowest,
    surfaceContainerLow: cs.surfaceContainerLow,
    surfaceContainer: cs.surfaceContainer,
    surfaceContainerHigh: cs.surfaceContainerHigh,
    surfaceContainerHighest: cs.surfaceContainerHighest,
  );
}

m3e.M3EColorVariant _toM3E(DynamicSchemeVariant v) => switch (v) {
  DynamicSchemeVariant.vibrant => m3e.M3EColorVariant.vibrant,
  DynamicSchemeVariant.fidelity => m3e.M3EColorVariant.fidelity,
  DynamicSchemeVariant.expressive ||
  DynamicSchemeVariant.content => m3e.M3EColorVariant.expressive,
  DynamicSchemeVariant.monochrome => m3e.M3EColorVariant.monochrome,
  DynamicSchemeVariant.neutral => m3e.M3EColorVariant.neutral,
  DynamicSchemeVariant.rainbow => m3e.M3EColorVariant.rainbow,
  DynamicSchemeVariant.fruitSalad => m3e.M3EColorVariant.fruitSalad,
  DynamicSchemeVariant.tonalSpot => m3e.M3EColorVariant.tonalSpot,
};

/// 供 m3e_core 组件使用的 material_ui 主题（M3E 组件读取的是 material_ui 的 Theme）。
///
/// [dynamicColorScheme] 传入时（莫奈取色）直接转换系统动态配色；否则用种子色生成 M3E 配色。
mui.ThemeData buildM3ETheme({
  required Brightness brightness,
  ColorScheme? dynamicColorScheme,
  Color seedColor = Colors.deepPurple,
  DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.tonalSpot,
}) {
  final cs = dynamicColorScheme != null
      ? _toMuiScheme(dynamicColorScheme)
      : (brightness == Brightness.dark
          ? m3e.M3EColorScheme.dark(
              seedColor: seedColor,
              variant: _toM3E(schemeVariant),
            )
          : m3e.M3EColorScheme.light(
              seedColor: seedColor,
              variant: _toM3E(schemeVariant),
            ));
  return mui.ThemeData(colorScheme: cs);
}

/// m3e_design 的 [M3ETheme] 用 `type` 属性覆盖了框架 [ThemeExtension.type]，
/// 导致 Flutter 3.47 按 `extension.type` 做键存取扩展时查不到（`.m3e` 访问器在
/// debug 下会断言）。因此这里不依赖扩展查找，直接用 m3e_design 的
/// `ColorScheme.toM3EThemeData()` 构建主题（内置 M3ETheme 设计令牌）。
///
/// ponytail: m3e_design 0.2.1 的 type 遮蔽 bug 未修，`extension<M3ETheme>()` 取不到；
/// 等上游修复后可改回纯净的 toM3EThemeData() 并正常用 .m3e 读取令牌。
ThemeData buildMigaTheme({
  required Brightness brightness,
  ColorScheme? dynamicColorScheme,
  Color seedColor = Colors.deepPurple,
  DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.tonalSpot,
  double scale = 1.0,
}) {
  final colorScheme = dynamicColorScheme ??
      _SeedSchemeCache.get(brightness, seedColor, schemeVariant);

  // 用 m3e_design 提供的方式构建主题：安装 M3ETheme 设计令牌（配色/排版/形状/间距/动效）
  final base = colorScheme.toM3EThemeData();
  if (scale == 1.0) return base;

  // 界面元素缩放：把字体、图标、组件尺寸与间距统一按比例放大/缩小
  final textTheme = _scaleTextTheme(base.textTheme, scale);
  final iconSize = 24.0 * scale;
  final buttonText = textTheme.labelLarge;

  return base.copyWith(
    textTheme: textTheme,
    iconTheme: base.iconTheme.copyWith(size: iconSize),
    primaryIconTheme: base.primaryIconTheme.copyWith(size: iconSize),
    // 让 Material 组件内部间距随缩放变化
    visualDensity: VisualDensity(
      horizontal: -(scale - 1) * 8,
      vertical: -(scale - 1) * 8,
    ),
    // 顶部应用栏
    appBarTheme: base.appBarTheme.copyWith(
      toolbarHeight: 56 * scale,
      titleTextStyle: textTheme.titleLarge,
    ),
    // 底部导航栏（NavigationBar）
    navigationBarTheme: base.navigationBarTheme.copyWith(
      height: 80 * scale,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(size: 24 * scale),
      ),
    ),
    // 顶部 Tab/分段控件
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: textTheme.titleSmall,
      unselectedLabelStyle: textTheme.titleSmall,
    ),
    // 滑杆
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 4 * scale,
      thumbSize: WidgetStatePropertyAll(
        Size(24 * scale, 24 * scale),
      ),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 24 * scale),
    ),
    // 列表项
    listTileTheme: base.listTileTheme.copyWith(
      minVerticalPadding: 8 * scale,
      horizontalTitleGap: 16 * scale,
      contentPadding: EdgeInsets.symmetric(horizontal: 16 * scale),
    ),
    // 复选框 / 单选
    checkboxTheme: base.checkboxTheme.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    radioTheme: base.radioTheme.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    // 进度条
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      linearMinHeight: 4 * scale,
    ),
    // 卡片边距与圆角随缩放
    cardTheme: base.cardTheme.copyWith(
      margin: EdgeInsets.all(4 * scale),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(64 * scale, 40 * scale),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(64 * scale, 40 * scale),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(64 * scale, 40 * scale),
        textStyle: buttonText,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 12 * scale,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: textTheme.labelLarge,
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(),
    snackBarTheme: base.snackBarTheme.copyWith(
      contentTextStyle: textTheme.bodyMedium,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      textStyle: textTheme.bodySmall,
      waitDuration: base.tooltipTheme.waitDuration,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      textStyle: textTheme.bodyMedium,
    ),
  );
}
