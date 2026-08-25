import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/data/deck_pool.dart';
import 'package:miga/main.dart';
import 'package:miga/models/card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    CardPool.instance.setCards([
      for (var i = 1; i <= 15; i++)
        CardData(id: 'c$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
    DeckPool.instance.setDeck([
      for (var i = 1; i <= 15; i++)
        CardData(id: 'c$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
  });

  tearDown(() {
    CardPool.instance.reset();
    DeckPool.instance.clear();
  });

  testWidgets('配装页右上角 M3E 下拉菜单可打开并执行动作', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    onboardingDone = true;

    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('配装').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 打开右上角菜单（仅三个点图标）
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('导入卡牌JSON'), findsOneWidget);
    expect(find.text('新建卡组'), findsOneWidget);

    // 点「新建卡组」→ 输入名称并确定 → 新建卡组
    final decksBefore = DeckPool.instance.savedDecks.length;
    await tester.tap(find.text('新建卡组'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).last, '新卡组');
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(DeckPool.instance.savedDecks.length, decksBefore + 1);

    debugDefaultTargetPlatformOverride = null;
  });
}
