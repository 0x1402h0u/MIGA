import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/data/deck_pool.dart';
import 'package:miga/main.dart';
import 'package:miga/models/card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CardPool.instance.setCards([
      const CardData(id: 'squirrel', name: '松鼠', count: 20),
      for (var i = 1; i <= 20; i++)
        CardData(id: 'c$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
  });

  tearDown(() {
    CardPool.instance.reset();
    DeckPool.instance.clear();
  });

  testWidgets('启动时无牌组，之后配置牌组后发牌页自动填充并可发牌', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    onboardingDone = true;
    DeckPool.instance.clear();

    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));

    // 切到发牌页：牌堆为空
    await tester.tap(find.text('发牌').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('空'), findsOneWidget);

    // 之后配置好牌组（发牌页已初始化）→ 牌堆应自动填充
    DeckPool.instance.setDeck([
      for (var i = 1; i <= 15; i++)
        CardData(id: 'c$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('空'), findsNothing);

    // 发牌应成功：空手牌提示消失
    await tester.tapAt(const Offset(400, 468));
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('你的手牌是空的'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
