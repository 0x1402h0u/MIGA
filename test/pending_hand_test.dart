import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miga/data/card_pool.dart';
import 'package:miga/data/deck_pool.dart';
import 'package:miga/data/local_store.dart';
import 'package:miga/main.dart';
import 'package:miga/models/card.dart';
import 'package:miga/screens/draw_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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

  tearDown(() {
    pendingHand = null;
    CardPool.instance.reset();
    DeckPool.instance.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  test('PendingHand 保存/读取/清除往返', () async {
    SharedPreferences.setMockInitialValues({});
    final hand = const PendingHand(
      handIds: ['a', 'b'],
      handColors: [0xFFFFFFFF, 0xFFE0E0E0],
      redDeckIds: ['c', 'd'],
      redDeckMax: 4,
      blueDeckIds: ['e'],
      blueDeckMax: 6,
      isRedFront: false,
    );
    await LocalStore.instance.savePendingHand(hand);
    final loaded = await LocalStore.instance.loadPendingHand();
    expect(loaded, isNotNull);
    expect(loaded!.handIds, ['a', 'b']);
    expect(loaded.handColors, [0xFFFFFFFF, 0xFFE0E0E0]);
    expect(loaded.redDeckIds, ['c', 'd']);
    expect(loaded.redDeckMax, 4);
    expect(loaded.blueDeckIds, ['e']);
    expect(loaded.blueDeckMax, 6);
    expect(loaded.isRedFront, isFalse);

    await LocalStore.instance.clearPendingHand();
    expect(await LocalStore.instance.loadPendingHand(), isNull);
  });

  Future<void> pumpMiga(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    onboardingDone = true;
    final card = const CardData(id: 'c1', name: '手牌卡');
    CardPool.instance.setCards([card]);
    DeckPool.instance.setDeck([card]);
    pendingHand = await LocalStore.instance.loadPendingHand();
    await tester.pumpWidget(const MigaApp());
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('重启后弹出恢复对局弹窗：重新载入回到发牌页且手牌还原',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.savePendingHand(
      const PendingHand(
        handIds: ['c1'],
        handColors: [0xFFFFFFFF],
        redDeckIds: ['c1'],
        redDeckMax: 1,
        blueDeckIds: ['c1'],
        blueDeckMax: 1,
        isRedFront: true,
      ),
    );
    await pumpMiga(tester);

    // 弹窗出现
    expect(find.text('恢复上次对局'), findsOneWidget);
    await tester.tap(find.text('重新载入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 让恢复 hand 的 setState 在新一帧呈现
    await tester.pump();

    // 切到发牌页（标题 + Tab 标签各一个），手牌已还原（不再显示空手牌提示，且出现该卡）
    expect(find.text('发牌'), findsNWidgets(2));
    expect(find.text('你的手牌是空的'), findsNothing);
    expect(find.text('手牌卡'), findsWidgets);
    // 恢复后存档仍反映实况（未错误清除）
    expect(await LocalStore.instance.loadPendingHand(), isNotNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('重新载入后：手牌在时禁止滑动切页，点按底部导航仍可切换',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.savePendingHand(
      const PendingHand(
        handIds: ['c1'],
        handColors: [0xFFFFFFFF],
        redDeckIds: ['c1'],
        redDeckMax: 1,
        blueDeckIds: ['c1'],
        blueDeckMax: 1,
        isRedFront: true,
      ),
    );
    await pumpMiga(tester);
    await tester.tap(find.text('重新载入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('手牌卡'), findsWidgets);

    // 手指滑动不换页（留在发牌页）
    await tester.drag(
      find.byType(TabBarView).first,
      const Offset(-400, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('我们的征途是星辰大海'), findsNothing);

    // 点按底部导航不受影响，能离开发牌页
    await tester.tap(find.text('主页').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('我们的征途是星辰大海'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('正常抽牌结束后手牌在，对局状态同步为进行中（禁用滑动）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    CardPool.instance.setCards([
      for (var i = 1; i <= 15; i++)
        CardData(id: '$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);
    DeckPool.instance.setDeck([
      for (var i = 1; i <= 15; i++)
        CardData(id: '$i', name: '卡牌$i', cost: 1, attack: 1, health: 1),
    ]);

    final inGame = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DrawScreen(
                    embedded: true,
                    onInGameChanged: inGame.add,
                  ),
                ),
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
    await tester.pump();

    // 加载首帧不发对局状态回调（初始为 false 隐含）

    // 抽牌（发牌动画期间手牌空 → 仍 false，结束时手牌非空 → true）
    await tester.tap(find.byIcon(Icons.back_hand));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 5500));
    await tester.pump();

    expect(inGame, contains(true));
    expect(find.text('你的手牌是空的'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('重启后弹窗选「放弃」：不切页并清除存档', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.savePendingHand(
      const PendingHand(
        handIds: ['c1'],
        handColors: [0xFFFFFFFF],
        redDeckIds: ['c1'],
        redDeckMax: 1,
        blueDeckIds: ['c1'],
        blueDeckMax: 1,
        isRedFront: true,
      ),
    );
    await pumpMiga(tester);

    expect(find.text('恢复上次对局'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 停留在主页，存档被清除
    expect(find.text('我们的征途是星辰大海'), findsOneWidget);
    expect(await LocalStore.instance.loadPendingHand(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}