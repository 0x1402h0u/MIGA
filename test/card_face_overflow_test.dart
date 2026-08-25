import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/widgets/card_face.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(CardPool.instance.reset);

  testWidgets('长文本卡面在多个尺寸下不溢出', (tester) async {
    const json = '['
        '{"no": "001", "name": "铃铛卡", "cost": 1, "attack": "铃铛", "health": "血祭（本回合献祭次数）", "skills": ["超长技能名称测试甲乙丙丁"]}'
        ']';
    CardPool.instance.importJson(json);
    final card = CardPool.instance.cards.single;

    for (final size in const [(120.0, 168.0), (160.0, 224.0), (240.0, 336.0)]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CardFace(
              card: card,
              width: size.$1,
              height: size.$2,
              reveal: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'CardFace $size 不应溢出');
    }
  });
}
