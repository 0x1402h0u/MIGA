import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('界面元素缩放实时生效（主题缩放）', (tester) async {
    onboardingDone = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    themeController.setUiScale(1.0);
    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));
    final baseBody = _bodyFontSize(tester);
    final baseIcon = _iconSize(tester);

    // 修改缩放 → 字体、图标等元素尺寸实时变化（先重建触发动画，再推进动画）
    themeController.setUiScale(1.25);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_bodyFontSize(tester), closeTo(baseBody * 1.25, 0.5));
    expect(_iconSize(tester), closeTo(baseIcon * 1.25, 0.5));

    themeController.setUiScale(1.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_bodyFontSize(tester), closeTo(baseBody, 0.5));

    debugDefaultTargetPlatformOverride = null;
  });
}

double _bodyFontSize(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return Theme.of(ctx).textTheme.bodyMedium!.fontSize!;
}

double _iconSize(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  return Theme.of(ctx).iconTheme.size ?? 24;
}
