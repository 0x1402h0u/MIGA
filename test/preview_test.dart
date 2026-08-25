import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/models/card.dart';
import 'package:miga/screens/deck_config_screen.dart';
import 'package:miga/widgets/game_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CardPool.instance.setCards([
      for (var i = 1; i <= 5; i++)
        CardData(id: '$i', name: '测试卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
  });

  tearDown(CardPool.instance.reset);

  testWidgets('长按卡牌展开预览，松开后能收回', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeckConfigScreen(
          key: UniqueKey(),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('测试卡牌1'), findsOneWidget);

    // 长按触发预览
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('测试卡牌1')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    // 预览放大卡应显示（GameCard）
    expect(find.byType(GameCard), findsWidgets);

    // 松开收回
    await gesture.up();
    await tester.pumpAndSettle();

    // 预览应被移除（配装页正常状态下没有 GameCard）
    expect(find.byType(GameCard), findsNothing);
    expect(find.text('测试卡牌1'), findsOneWidget);
  });
}
