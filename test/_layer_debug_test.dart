import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/main.dart';
import 'package:miga/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('settings press layer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    themeController.setUseMonet(false);
    themeController.setSeedColor(Colors.red);
    themeController.setUiScale(1.0);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMigaTheme(brightness: Brightness.light),
        darkTheme: buildMigaTheme(brightness: Brightness.dark),
        builder: (context, child) => ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => mui.Theme(
            data: buildM3ETheme(brightness: Brightness.light),
            child: child!,
          ),
        ),
        home: const SettingsPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final allTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d != null)
        .toList();
    debugPrint('TEXTS: $allTexts');

    await tester.scrollUntilVisible(
      find.text('深色模式'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final switchRow = find.text('深色模式');
    final center = tester.getCenter(switchRow);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 60));
    await expectLater(
      find.byType(SettingsPage),
      matchesGoldenFile('goldens/layer_press_current.png'),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
  });
}