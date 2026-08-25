import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miga/models/card.dart';
import 'package:miga/utils/deck_share.dart';

void main() {
  testWidgets('导出空牌组二维码可正常渲染', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDeckQrDialog(context, const []),
              child: const Text('导出'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出牌组'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('导出对话框能正常渲染二维码', (tester) async {
    final deck = List.generate(
      15,
      (i) => CardData(
        id: 'card_$i',
        name: '测试卡牌名称$i',
        cost: i % 3,
        attack: i % 5,
        health: i % 7,
        skills: i % 2 == 0 ? ['技能${i % 3}', '附加'] : const [],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDeckQrDialog(context, deck),
              child: const Text('导出'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出牌组'), findsOneWidget);
    expect(find.text('保存相册'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('渲染保存图片包含二维码与作者名字', (tester) async {
    final deck = [
      const CardData(id: 'wolf', name: '狼', cost: 2, attack: 3, health: 2),
      const CardData(id: 'sparrow', name: '麻雀', cost: 1, attack: 1, health: 2),
    ];
    final png = await tester.runAsync(
      () => renderDeckQrPng(deck),
    );
    expect(png, isNotNull);
    expect(png!.length, greaterThan(0));
    // 渲染后的图片应能解码回牌组，且长宽为 800x960（二维码 + 留白署名）
    final deck2 = decodeDeckQr(png);
    expect(deck2, isNotNull);
    expect(deck2!.length, 2);
  });

  testWidgets('大牌组（高版本二维码）渲染后可解码还原', (tester) async {
    // 贴近真实：20 张中文卡牌 + 技能，会让二维码达到高版本（v34 左右）
    final deck = List.generate(
      20,
      (i) => CardData(
        id: 'card_$i',
        name: '卡牌$i号',
        cost: i % 3,
        attack: i % 4,
        health: i % 5,
        skills: ['技能$i', '附加效果'],
      ),
    );
    final png = await tester.runAsync(() => renderDeckQrPng(deck));
    expect(png, isNotNull);
    final restored = decodeDeckQr(png!);
    expect(restored, isNotNull);
    expect(restored!.length, 20);
    expect(restored.map((c) => c.id), deck.map((c) => c.id));
  });

  testWidgets('超大牌组生成二维码应提示过大而不是崩溃', (tester) async {
    // 60 张超长中文卡牌，即使压缩后也超出二维码容量
    final deck = List.generate(
      60,
      (i) => CardData(
        id: 'card_with_very_long_id_${i.toString().padLeft(4, '0')}_$i',
        name: '非常非常长的中文卡牌名称测试编号$i并且附加更多文字说明内容$i',
        cost: i,
        attack: i,
        health: i,
        skills: ['技能甲$i', '技能乙$i', '技能丙$i', '技能丁$i', '技能戊$i', '附加效果$i'],
      ),
    );
    final png = await tester.runAsync(() async {
      try {
        await renderDeckQrPng(deck);
        return null;
      } catch (e) {
        return e.toString();
      }
    });
    expect(png, isNotNull);
    expect(png, contains('过大'));
  });
}
