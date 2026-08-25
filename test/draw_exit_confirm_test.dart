import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/data/deck_pool.dart';
import 'package:miga/models/card.dart';
import 'package:miga/screens/draw_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CardPool.instance.setCards([
      for (var i = 1; i <= 15; i++)
        CardData(id: '$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
    DeckPool.instance.setDeck([
      for (var i = 1; i <= 15; i++)
        CardData(id: '$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
  });

  tearDown(() {
    CardPool.instance.reset();
    DeckPool.instance.clear();
  });

  Future<void> openDrawScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DrawScreen()),
              ),
              child: const Text('打开发牌页'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开发牌页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('发牌后返回需确认，取消留在页面、退出返回上一页', (tester) async {
    await openDrawScreen(tester);

    // 点击发牌（第一次发 4 张，每张约 1 秒延时，等它完全结束）
    await tester.tap(find.byIcon(Icons.back_hand));
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));

    // 手牌已发出
    expect(find.text('退出发牌'), findsNothing);

    // 触发返回 → 弹出确认框
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('退出发牌'), findsOneWidget);

    // 取消：留在发牌页
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('退出发牌'), findsNothing);
    expect(find.byType(DrawScreen), findsOneWidget);

    // 再次返回 → 确认退出
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('退出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DrawScreen), findsNothing);
    expect(find.text('打开发牌页'), findsOneWidget);
  });

  testWidgets('未发牌时返回直接退出不弹框', (tester) async {
    await openDrawScreen(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('退出发牌'), findsNothing);
    expect(find.byType(DrawScreen), findsNothing);
    expect(find.text('打开发牌页'), findsOneWidget);
  });
}
