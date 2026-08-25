import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:m3e_design/m3e_design.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('M3E 组件读取到的是与应用同步的 material_ui 主题', (tester) async {
    onboardingDone = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    themeController.setUseMonet(false);
    themeController.setSeedColor(Colors.red);
    themeController.setUiScale(1.0);

    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));

    final btnFinder = find.byType(M3EFilledButton).hitTestable();
    expect(btnFinder, findsWidgets);
    final ctx = tester.element(btnFinder.first);
    final expected = Theme.of(ctx).colorScheme.primary;
    // 回退主题（material_ui 默认）的 primary 为 M3 默认紫色
    expect(expected, isNot(const Color(0xFF6750A4)));

    // M3E 组件读取的是 material_ui 的 Theme，应取到与应用主色一致的颜色
    final muiPrimary = mui.Theme.of(ctx).colorScheme.primary;
    expect(muiPrimary, expected);

    // 应用主题已用 m3e_design 构建：安装的 M3ETheme 设计令牌随主题存在
    final themeData = Theme.of(ctx);
    final hasM3ETheme =
        themeData.extensions.values.any((e) => e is M3ETheme);
    expect(hasM3ETheme, isTrue);

    onboardingDone = true;
    debugDefaultTargetPlatformOverride = null;
  });
}
