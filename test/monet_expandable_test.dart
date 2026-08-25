import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  M3EExpandableItem item(WidgetTester tester) =>
      tester.widget<M3EExpandableItem>(find.byType(M3EExpandableItem).first);

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu).hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('设置').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('莫奈取色可展开卡片：收起 = 开启系统取色，展开 = 关闭', (tester) async {
    onboardingDone = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    themeController.setUseMonet(false);
    themeController.setUiScale(1.0);

    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));
    await openSettings(tester);

    // 默认未开启莫奈取色 → 展开
    expect(themeController.useMonet, isFalse);
    expect(item(tester).isExpanded, isTrue);

    // 点击头部收起 → 开启系统取色
    await tester.tap(find.text('莫奈取色系统'));
    await tester.pump();
    expect(item(tester).isExpanded, isFalse);
    expect(themeController.useMonet, isTrue);

    // 再点展开 → 关闭系统取色
    await tester.tap(find.text('莫奈取色系统'));
    await tester.pump();
    expect(item(tester).isExpanded, isTrue);
    expect(themeController.useMonet, isFalse);

    debugDefaultTargetPlatformOverride = null;
  });
}
