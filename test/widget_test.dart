import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/data/deck_pool.dart';
import 'package:miga/main.dart';
import 'package:miga/models/card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // 生物识别通道在测试的假异步环境下会挂起，mock 成验证通过。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/local_auth'),
    (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
        case 'authenticate':
        case 'isEnrolled':
          return true;
      }
      return null;
    },
  );

  // 测试环境默认 android 平台会走真实 WebView（需要平台视图），
  // 强制走桌面端回退分支（外部浏览器按钮）以保证测试可跑。
  void useLinuxFallback() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    onboardingDone = true; // 跳过新手引导
  }

  void resetPlatform() {
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('FAB opens draw screen, tabs switch pages',
      (WidgetTester tester) async {
    useLinuxFallback();
    DeckPool.instance.setDeck([
      for (var i = 1; i <= 15; i++)
        CardData(id: '$i', name: 'Card$i'),
    ]);
    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));

    // 主页 is active (nav label) with title
    expect(find.text('主页').hitTestable(), findsOneWidget);
    expect(find.text('我们的征途是星辰大海').hitTestable(), findsOneWidget);
    expect(find.text('MIGA-谜咖').hitTestable(), findsOneWidget);
    expect(find.text('Make Inscryption Great Again!').hitTestable(), findsOneWidget);
    // 发牌 Tab 直达发牌页
    await tester.tap(find.text('发牌').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('你的手牌是空的'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back).hitTestable(), findsNothing);
    // 首抽主按钮（Tab 图标 + 主按钮各一）
    expect(find.byIcon(Icons.back_hand).hitTestable(), findsNWidgets(2));

    // 切回主页
    await tester.tap(find.text('主页').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('主页').hitTestable(), findsOneWidget);

    // switch to 配装 (deck config)
    await tester.tap(find.text('配装').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 卡组下拉的选中项 chip 动画需要多帧展开
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('配装').hitTestable(), findsNWidgets(2));
    expect(find.text('牌库').hitTestable(), findsOneWidget);
    // 右侧牌组框标题：下拉显示卡组名（默认卡组）
    expect(find.text('默认卡组').hitTestable(), findsOneWidget);
    expect(find.text('确认牌组 (15/20)').hitTestable(), findsOneWidget);

    // 打开侧边抽屉 -> 进入个人资料编辑页
    await tester.tap(find.byIcon(Icons.menu).hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('个人').hitTestable(), findsOneWidget);
    await tester.tap(find.text('个人').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('编辑个人信息'), findsOneWidget);
    expect(find.text('MIGA 玩家'), findsOneWidget);

    // 返回 -> 重新打开抽屉 -> 进入设置页
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.menu).hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('设置').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final dark = find.text('深色模式');
    await tester.scrollUntilVisible(
      dark,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(dark, findsOneWidget);
    resetPlatform();
  });

  testWidgets('发牌 Tab 无牌组时提示配置', (WidgetTester tester) async {
    useLinuxFallback();
    DeckPool.instance.clear();
    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));

    // 直接切到发牌 Tab：空牌堆应显示空手牌提示
    await tester.tap(find.text('发牌').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('你的手牌是空的'), findsOneWidget);
    expect(find.text('尚未配置牌组'), findsNothing);
    resetPlatform();
  });

  testWidgets('first launch shows onboarding', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    onboardingDone = false;
    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('MIGA-谜咖'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 导入牌库页：按钮为「跳过」
    expect(find.text('导入牌库'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    // 赞助入口页
    expect(find.text('赞助'), findsOneWidget);
    expect(find.text('打开赞助页面'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 亮点介绍页（清屏后浮现，等待后出现「我已了解」）
    expect(find.text('亮点介绍'), findsOneWidget);
    expect(find.text('完全免费'), findsOneWidget);
    expect(find.text('Material Design'), findsOneWidget);
    expect(find.text('我已了解'), findsOneWidget);
    await tester.tap(find.text('我已了解'));
    await tester.pumpAndSettle();

    // 最后一页：欢迎使用谜咖
    expect(find.text('欢迎使用谜咖'), findsOneWidget);
    expect(find.text('开始使用'), findsOneWidget);
    await tester.tap(find.text('开始使用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('我们的征途是星辰大海'), findsOneWidget);

    onboardingDone = true;
    debugDefaultTargetPlatformOverride = null;
  });
}
