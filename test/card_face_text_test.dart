import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/widgets/card_face.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(CardPool.instance.reset);

  testWidgets('卡面显示中文 attack/health 提示文字', (tester) async {
    const json = '['
        '{"no": "001", "name": "铃铛卡", "cost": 1, "attack": "铃铛", "health": "血祭（本回合献祭次数）", "skills": []}'
        ']';
    CardPool.instance.importJson(json);
    final card = CardPool.instance.cards.single;
    expect(card.attackText, '铃铛');
    expect(card.healthText, '血祭（本回合献祭次数）');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardFace(card: card, width: 240, height: 336, reveal: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('铃铛'), findsOneWidget);
    expect(find.text('血祭（本回合献祭次数）'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('长文本血量不溢出（红鹿）', (tester) async {
    const json = '['
        '{"no": "050", "name": "红鹿", "cost": 2, "attack": 1, "health": "血祭（本回合献祭次数）", "skills": ["冲刺能手"]}'
        ']';
    CardPool.instance.importJson(json);
    final card = CardPool.instance.cards.single;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardFace(card: card, width: 240, height: 336, reveal: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('血祭（本回合献祭次数）'), findsOneWidget);
  });
}
