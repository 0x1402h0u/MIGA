import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/data/deck_pool.dart';
import 'package:miga/models/card.dart';
import 'package:miga/screens/deck_config_screen.dart';
import 'package:miga/screens/draw_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CardPool.instance.setCards([
      for (var i = 1; i <= 20; i++)
        CardData(
          id: '$i',
          name: '测试卡牌$i',
          cost: 1,
          attack: 0,
          health: 0,
          attackText: '铃铛',
          healthText: '血祭（本回合献祭次数）',
        ),
    ]);
    DeckPool.instance.setDeck(CardPool.instance.cards.take(15).toList());
  });

  tearDown(() {
    CardPool.instance.reset();
    DeckPool.instance.clear();
  });

  testWidgets('手机尺寸下配装页不溢出', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeckConfigScreen(key: UniqueKey()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机尺寸下发牌页不溢出', (tester) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DrawScreen(),
      ),
    ));
    // 发牌页有无限循环动画（转轮自转），pumpAndSettle 会超时，
    // 改用固定帧泵血以检查首帧布局是否溢出。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
